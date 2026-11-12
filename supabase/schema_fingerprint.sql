-- Ignore PostgreSQL 18 NOT NULL constraint objects. Column nullability is checked separately.
select jsonb_build_object(
'tables',(select jsonb_agg(jsonb_build_object(
'name',n.nspname||'.'||c.relname,'rls',c.relrowsecurity,
'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
'constraints',(select jsonb_agg(jsonb_build_object('name',co.conname,'definition',pg_get_constraintdef(co.oid)) order by co.conname) from pg_constraint co where co.conrelid=c.oid and co.contype <> 'n'),
'policies',(select jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polrelid=c.oid)) order by n.nspname,c.relname)
from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r' and (n.nspname='fastpas_private' or(n.nspname='public' and c.relname like 'pos_%'))),
'functions',(select jsonb_agg(jsonb_build_object(
'name',n.nspname||'.'||p.proname,'args',oidvectortypes(p.proargtypes),'result',pg_get_function_result(p.oid),'body',replace(p.prosrc,E'\r',''),'security_definer',p.prosecdef,'volatility',p.provolatile,'config',p.proconfig,
'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')) order by n.nspname,p.proname,oidvectortypes(p.proargtypes))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='fastpas_private' or(n.nspname='public' and p.proname like 'pos_%'))
) as schema;
