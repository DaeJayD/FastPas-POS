import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/preview/management_samples.dart';
import 'package:vasenizzpos/dashboard/home_screen.dart';
import 'package:vasenizzpos/users/users_page.dart';
import 'package:vasenizzpos/suppliers/suppliers_creen.dart';
import 'package:vasenizzpos/employees/employee_page.dart';
import 'package:vasenizzpos/employees/emp_profile.dart';
import 'package:vasenizzpos/inventory/inventory_screen.dart';
import 'package:vasenizzpos/inventory/add_new_item.dart';
import 'package:vasenizzpos/inventory/brand_inventory.dart';
import 'package:vasenizzpos/inventory/inventory_history.dart';
import 'package:vasenizzpos/suppliers/supplier_products_screen.dart';
import 'package:vasenizzpos/reports/logs.dart';
import 'package:vasenizzpos/branches/components/calendar_events.dart';
import 'package:vasenizzpos/products/allproducts_screen.dart';
import 'package:vasenizzpos/reports/reports_page.dart';
import 'package:vasenizzpos/reports/generate_report_page.dart';
import 'package:vasenizzpos/sales/sales_history_page.dart';
import 'package:vasenizzpos/sales/receipt_page.dart';
import 'package:vasenizzpos/branches/carmen_branch.dart';
import 'package:vasenizzpos/branches/jasaan_branch.dart';
import 'package:vasenizzpos/branches/puerto_branch.dart';
import 'package:vasenizzpos/inventory/branchinventory/carmen_inventory.dart';
import 'package:vasenizzpos/inventory/branchinventory/jasaan_inventory.dart';
import 'package:vasenizzpos/inventory/branchinventory/puerto_inventory.dart';

Future<void> open(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint(details.toString());
    previousHandler?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = previousHandler;
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: Volt.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late SampleStoreTransport transport;
  setUp(() {
    transport = enableManagementSamples();
  });
  tearDown(() async {
    await StoreConnection.previewClient?.dispose();
    StoreConnection.previewClient = null;
    transport.close();
  });
  final pages = <String, Widget Function()>{
    'brand stock': () => const BrandInventoryPage(
      brandName: 'Everyday',
      brandId: 'brand1',
      fullName: 'Alex Santos',
      role: 'owner',
      branchManager: 'Alex Santos',
      branchCode: 'MAIN',
      branchName: 'Main Branch',
      userId: 'preview',
    ),
    'stock history': () => const InventoryHistoryScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
    ),
    'supplier products': () => const SupplierProductsScreen(
      supplier: {'id': 'supplier1', 'name': 'Everyday Supply Co.'},
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
    ),
    'activity logs': () => const ActivityLogsPage(logs: []),
    'calendar form': () => Scaffold(
      body: CalendarEventDialog(
        selectedDate: DateTime.now(),
        branchId: 'b1',
        userId: 'preview',
        onEventChanged: () {},
      ),
    ),
    'overview': () => const HomeScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
    ),
    'staff': () => const UsersPage(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
    ),
    'suppliers': () => const SuppliersScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
    ),
    'profile': () => const UserProfileScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
    ),
    'employee details': () =>
        const EmployeeProfilePage(userId: 'preview', userName: 'Alex Santos'),
    'inventory': () => const InventoryPage(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
    ),
    'catalog': () => const AllProductsInventoryScreen(
      fullName: 'Alex Santos',
      role: 'owner',
    ),
    'add item': () => const AddNewItemPage(
      brandId: 'brand1',
      branchId: 'b1',
      brandName: 'Everyday',
      branchName: 'Main Branch',
      userId: 'preview',
    ),
    'reports': () => const ViewReportsPage(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
    ),
    'export': () => const GenerateReportPage(),
    'history': () => const SalesHistoryPage(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
    ),
    'Carmen': () => const CarmenScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Carmen',
    ),
    'Jasaan': () => const JasaanScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Jasaan',
    ),
    'Puerto': () => const PuertoScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Puerto',
    ),
    'Carmen stock': () => const CarmenInventory(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Carmen',
    ),
    'Jasaan stock': () => const JasaanInventory(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Jasaan',
    ),
    'Puerto stock': () => const PuertoInventory(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Puerto',
    ),
  };
  test('sample reads return fixture rows', () async {
    final rows = await StoreConnection.client.from('branches').select();
    expect(rows.length, 5);
  });
  for (final size in [const Size(360, 800), const Size(1024, 768)]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} fits ${size.width} with larger text', (
        tester,
      ) async {
        await open(tester, entry.value(), size);
        expect(tester.takeException(), isNull);
        // Exercise the lower half of scrollable forms and reports as well.
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          final state = tester.state<ScrollableState>(scroll.first);
          if (state.position.hasContentDimensions) {
            state.position.jumpTo(state.position.maxScrollExtent);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(transport.rejectedWrites, 0);
      });
    }
  }
  testWidgets('history opens saved line items and preserves back navigation', (
    tester,
  ) async {
    await open(tester, pages['history']!(), const Size(390, 844));
    await tester.ensureVisible(find.text('View receipt'));
    await tester.tap(find.text('View receipt'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptPage), findsOneWidget);
    expect(find.text('Bottled water'), findsOneWidget);
    expect(find.text('Start a new sale'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sales history'), findsOneWidget);
    expect(transport.rejectedWrites, 0);
  });
  testWidgets('supplier form validates and fits above the phone keyboard', (
    tester,
  ) async {
    await open(tester, pages['suppliers']!(), const Size(360, 800));
    await tester.tap(find.byTooltip('Add New Supplier'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter supplier name'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(transport.rejectedWrites, 0);
  });
  testWidgets(
    'stock filter can be applied and cleared without reloading data',
    (tester) async {
      await open(tester, pages['brand stock']!(), const Size(390, 844));
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Out of Stock'));
      await tester.pumpAndSettle();
      expect(find.text('Stock: Out of Stock'), findsOneWidget);
      expect(find.text('No products found'), findsOneWidget);
      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Bottled water'), findsOneWidget);
      expect(transport.rejectedWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );
  test('sample transport rejects mutations', () async {
    await expectLater(
      StoreConnection.client.from('products').insert({'name': 'Unsafe'}),
      throwsA(anything),
    );
    expect(transport.rejectedWrites, 1);
  });
}
