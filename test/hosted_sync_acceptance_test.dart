import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/hybrid/local_store.dart';
import 'package:vasenizzpos/hybrid/sync_service.dart';
import 'package:vasenizzpos/workspaces/workspace_repository.dart';

/// Uses the real project transport, with controlled disconnects at the client.
class RegisterTransport extends http.BaseClient {
  RegisterTransport(this.origin);
  final String origin;
  final _client = http.Client();
  bool offline = false;
  bool loseSaleReply = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != origin) {
      throw StateError('A hosted request targeted a different project.');
    }
    if (offline) throw http.ClientException('Simulated offline register');
    request.followRedirects = false;
    final response = await _client.send(request);
    if (loseSaleReply &&
        request.url.path.endsWith('/rpc/pos_sync_cash_sale') &&
        response.statusCode == 200) {
      loseSaleReply = false;
      await response.stream.drain<void>();
      throw http.ClientException('Simulated lost sale acknowledgment');
    }
    return response;
  }

  @override
  void close() => _client.close();
}

void main() {
  const enabled = bool.fromEnvironment('FASTPAS_HOSTED_ACCEPTANCE');
  test(
    'Two SQLite registers recover cash uploads against the hosted project',
    () async {
      final raw = jsonDecode(
        await File('config/acceptance.local.json').readAsString(),
      ) as Map<String, dynamic>;
      final uri = Uri.parse(raw['projectUrl'] as String);
      final project = raw['expectedProjectRef'] as String;
      final key = raw['publicKey'] as String;
      final accounts = raw['accounts'] as Map<String, dynamic>;
      final credentials = [
        for (final name in ['ownerA', 'ownerB', 'staff'])
          Map<String, dynamic>.from(accounts[name] as Map),
      ];
      var publicKey = RegExp(r'^sb_publishable_[a-zA-Z0-9_-]+$').hasMatch(key);
      if (key.split('.').length == 3) {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))),
        ) as Map<String, dynamic>;
        publicKey = claims['role'] == 'anon';
      }
      if (raw['allowTestWrites'] != true ||
          !RegExp(r'^[a-z0-9-]+$').hasMatch(project) ||
          uri.scheme != 'https' ||
          uri.host != '$project.supabase.co' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          !['', '/'].contains(uri.path) ||
          uri.hasQuery ||
          uri.hasFragment ||
          !publicKey ||
          credentials.any(
            (account) =>
                account['email'] is! String ||
                !(account['email'] as String).contains('@') ||
                account['password'] is! String ||
                (account['password'] as String).length < 8 ||
                account['password'] == 'REPLACE_LOCALLY',
          ) ||
          credentials
                  .map(
                    (account) =>
                        (account['email'] as String).trim().toLowerCase(),
                  )
                  .toSet()
                  .length !=
              3) {
        throw StateError(
          'Use the opted-in development acceptance configuration.',
        );
      }

      sqfliteFfiInit();
      final root = await Directory.systemTemp.createTemp('fastpas-hosted-');
      final transports = List.generate(3, (_) => RegisterTransport(uri.origin));
      final clients = [
        for (final transport in transports)
          SupabaseClient(
            uri.origin,
            key,
            httpClient: transport,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
      ];
      final stores = <LocalStore>[];
      final checks = <String>[];
      final saleIds = <String>[];
      final business = WorkspaceRepository.newRequestId();
      final report = <String, dynamic>{
        'projectRef': project,
        'businessId': business,
        'localDirectory': root.path,
        'status': 'running',
        'checks': checks,
        'saleIds': saleIds,
      };
      final reportFile = File('config/phase9-hosted-sync.local.json');
      final runFile = File('config/phase9-hosted-sync-$business.local.json');
      Future<void> record() async {
        final text = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
        await runFile.writeAsString(text);
        await reportFile.writeAsString(text);
      }

      Future<void> check(bool condition, String label) async {
        expect(condition, isTrue, reason: label);
        checks.add(label);
        await record();
      }

      String stage = 'verified account sign-in';
      var passed = false;
      try {
        await record();
        final users = <User>[];
        for (var i = 0; i < clients.length; i++) {
          final account = credentials[i];
          await clients[i].auth.signInWithPassword(
            email: (account['email'] as String).trim().toLowerCase(),
            password: account['password'] as String,
          );
          final user = (await clients[i].auth.getUser()).user!;
          await check(
            user.emailConfirmedAt != null && user.role == 'authenticated',
            'Account $i is verified by hosted Auth',
          );
          users.add(user);
        }
        await check(
          users.map((user) => user.id).toSet().length == 3,
          'Hosted identities are distinct',
        );
        final owner = clients[0], unrelated = clients[1], staff = clients[2];
        stage = 'dedicated fixture setup';
        await owner.rpc(
          'pos_create_business',
          params: {
            'request_id': business,
            'business_name': 'Offline acceptance $business',
            'branch_name': 'Main',
          },
        );
        final branch =
            (await owner
                    .from('pos_branches')
                    .select('id')
                    .eq('business_id', business)
                    .single())['id']
                as String;
        report['branchId'] = branch;
        await record();
        final product = await owner.rpc(
          'pos_add_item',
          params: {
            'business': business,
            'branch': branch,
            'product_name': 'Acceptance water',
            'product_sku': 'OFFLINE',
            'unit_cents': 2500,
            'opening_quantity': 10,
          },
        ) as String;
        final code = await owner.rpc(
          'pos_invite_staff',
          params: {
            'business': business,
            'branch': branch,
            'invite_email': users[2].email,
            'invite_role': 'cashier',
          },
        ) as String;
        await staff.rpc('pos_accept_invitation', params: {'invite_code': code});
        Future<LocalStore> open(int register) async {
          final directory = await Directory(
            path.join(root.path, 'register-$register'),
          ).create();
          final store = await LocalStore.open(
            userId: users[register == 0 ? 0 : 2].id,
            businessId: business,
            branchId: branch,
            factory: databaseFactoryFfi,
            directory: directory.path,
          );
          stores.add(store);
          return store;
        }

        Future<List<dynamic>> devices() async => await owner.rpc(
          'pos_branch_selling_devices',
          params: {'p_business': business, 'p_branch': branch},
        ) as List<dynamic>;
        Future<void> denied(
          Future<dynamic> Function() action,
          String label,
        ) async {
          try {
            await action();
          } on PostgrestException catch (error) {
            await check(error.code == '42501', label);
            return;
          }
          throw StateError('An unauthorized hosted request succeeded.');
        }

        var a = await open(0), b = await open(1);
        stage = 'initial catalog and registration';
        await Future.wait([
          SyncService(owner, a).synchronize(force: true),
          SyncService(staff, b).synchronize(force: true),
        ]);
        final aDevice = await a.deviceId, bDevice = await b.deviceId;
        final registered = await devices();
        await check(
          registered.length == 2 &&
              registered.map((row) => row['device_id']).toSet().containsAll([
                aDevice,
                bDevice,
              ]),
          'Two independent register codes appear in the owner branch list',
        );

        stage = 'offline checkout and SQLite reopen';
        transports[0].offline = transports[2].offline = true;
        final saleA = await a.checkout({product: 1}, 2500);
        final saleB = await b.checkout({product: 2}, 5000);
        saleIds.addAll([saleA, saleB]);
        final payloadA = (await a.receipts()).single['payload'];
        final payloadB = (await b.receipts()).single['payload'];
        await record();
        await a.close();
        await b.close();
        stores.remove(a);
        stores.remove(b);
        a = await open(0);
        b = await open(1);
        await check(
          await a.deviceId == aDevice && await b.deviceId == bDevice,
          'Reopening SQLite preserves both device IDs',
        );
        await check(
          (await a.receipts()).single['payload'] == payloadA &&
              (await b.receipts()).single['payload'] == payloadB &&
              (await a.products()).single['quantity'] == 9 &&
              (await b.products()).single['quantity'] == 8,
          'Offline receipts and one local stock deduction survive reopening',
        );

        stage = 'lost cloud acknowledgment';
        transports[0].offline = transports[2].offline = false;
        transports[0].loseSaleReply = true;
        await expectLater(
          SyncService(owner, a).synchronize(),
          throwsA(isA<http.ClientException>()),
        );
        await check(
          (await a.receipts()).single['status'] == 'pending' &&
              (await a.products()).single['quantity'] == 9,
          'A committed sale with a lost reply retains its pending local receipt',
        );
        await check(
          await SyncService(owner, a).synchronize() == SyncOutcome.waiting,
          'Automatic sync respects the saved retry deadline',
        );
        stage = 'simultaneous reconnect and exact receipt retries';
        await Future.wait([
          SyncService(owner, a).synchronize(force: true),
          SyncService(staff, b).synchronize(force: true),
        ]);
        await Future.wait([
          SyncService(owner, a).synchronize(force: true),
          SyncService(staff, b).synchronize(force: true),
        ]);
        final saved = await owner
            .from('pos_cash_sales')
            .select('id,device_id')
            .eq('business_id', business);
        await check(
          saved.length == 2 &&
              saved.any(
                (row) => row['id'] == saleA && row['device_id'] == aDevice,
              ) &&
              saved.any(
                (row) => row['id'] == saleB && row['device_id'] == bDevice,
              ),
          'The cloud contains each original receipt once with its original device',
        );
        await check(
          (await a.products()).single['quantity'] == 7 &&
              (await b.products()).single['quantity'] == 7 &&
              (await a.receipts()).single['status'] == 'synced' &&
              (await b.receipts()).single['status'] == 'synced',
          'Both local snapshots converge after the three sold units',
        );
        final retried = await devices();
        await check(
          retried.length == 2 &&
              registered.every(
                (original) => retried.any(
                  (row) =>
                      row['id'] == original['id'] &&
                      row['registered_at'] == original['registered_at'],
                ),
              ),
          'Concurrent repeated check-ins preserve the two original registrations',
        );

        stage = 'account and branch isolation';
        final listParams = {'p_business': business, 'p_branch': branch};
        await denied(
          () => unrelated.rpc('pos_branch_selling_devices', params: listParams),
          'An unrelated owner cannot read the registry',
        );
        await denied(
          () => staff.rpc('pos_branch_selling_devices', params: listParams),
          'Cashier access cannot read the owner registry',
        );
        await expectLater(
          SyncService(unrelated, a).synchronize(),
          throwsStateError,
        );
        await check(
          (await a.receipts()).single['payload'] == payloadA,
          'An account change leaves the original local receipt intact',
        );

        final otherBranch = WorkspaceRepository.newRequestId();
        report['otherBranchId'] = otherBranch;
        await record();
        await owner.rpc(
          'pos_create_branch',
          params: {
            'business': business,
            'request_id': otherBranch,
            'branch_name': 'Reassignment check',
            'branch_address': '',
          },
        );
        final thirdSale = await b.checkout({product: 1}, 2500);
        saleIds.add(thirdSale);
        await record();
        await owner.rpc(
          'pos_set_staff_branches',
          params: {
            'business': business,
            'member': users[2].id,
            'branches': [otherBranch],
          },
        );
        await expectLater(
          SyncService(staff, b).synchronize(force: true),
          throwsStateError,
        );
        await check(
          !await b.canSell() &&
              (await b.pendingReceipts()).single['id'] == thirdSale,
          'Known branch removal blocks selling and retains the pending sale',
        );
        await denied(
          () => staff.rpc(
            'pos_register_selling_device',
            params: {...listParams, 'p_device': bDevice},
          ),
          'Removed branch access cannot refresh registration',
        );
        final otherDevices = await owner.rpc(
          'pos_branch_selling_devices',
          params: {'p_business': business, 'p_branch': otherBranch},
        ) as List<dynamic>;
        await check(
          otherDevices.isEmpty && (await devices()).length == 2,
          'Another branch excludes the original registrations',
        );
        stage = 'restored access and pending sale recovery';
        await owner.rpc(
          'pos_set_staff_branches',
          params: {
            'business': business,
            'member': users[2].id,
            'branches': [branch],
          },
        );
        await SyncService(staff, b).synchronize(force: true);
        await SyncService(owner, a).synchronize(force: true);
        await check(
          await b.canSell() &&
              (await b.pendingReceipts()).isEmpty &&
              (await a.products()).single['quantity'] == 6 &&
              (await b.products()).single['quantity'] == 6,
          'Restoring access uploads the retained sale and both stocks converge',
        );
        report['status'] = 'passed';
        passed = true;
      } catch (error, stack) {
        report['status'] = 'failed';
        report['failedStage'] = stage;
        report['errorType'] = error.runtimeType.toString();
        if (error is TypeError) {
          report['typeError'] = error.toString();
          report['failureStack'] = stack
              .toString()
              .split('\n')
              .take(6)
              .toList();
        }
        if (error is PostgrestException) report['errorCode'] = error.code;
        throw StateError(
          'Hosted acceptance failed during $stage. Inspect the local report.',
        );
      } finally {
        final closed = await Future.wait([
          for (final client in clients)
            () async {
              try {
                if (client.auth.currentSession != null) {
                  await client.auth.signOut(scope: SignOutScope.local);
                }
                return true;
              } catch (_) {
                return false;
              } finally {
                await client.dispose();
              }
            }(),
        ]);
        report['sessionsClosed'] = closed.every((value) => value);
        for (final store in stores) {
          await store.close();
        }
        for (final transport in transports) {
          transport.close();
        }
        await record();
        if (passed) expect(report['sessionsClosed'], isTrue);
      }
    },
    skip: enabled ? false : 'Requires explicit hosted test-write opt-in.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
