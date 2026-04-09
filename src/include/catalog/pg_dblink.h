/*-------------------------------------------------------------------------
 *
 * pg_dblink.h
 *    definition of the "database link" system catalog (pg_dblink)
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/catalog/pg_dblink.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_DBLINK_H
#define PG_DBLINK_H

#include "catalog/genbki.h"
#include "catalog/pg_dblink_d.h"

CATALOG(pg_dblink,9382,DbLinkRelationId)
{
	Oid			oid;
	NameData	dblname;
	Oid			dblowner BKI_LOOKUP(pg_authid);
	Oid			dblserver BKI_LOOKUP(pg_foreign_server);
	char		dblauth;

#ifdef CATALOG_VARLEN
	text		dbloptions[1];
#endif
} FormData_pg_dblink;

typedef FormData_pg_dblink * Form_pg_dblink;

#define DBLINK_AUTH_FIXED		'f'
#define DBLINK_AUTH_CURRENT_USER	'c'

DECLARE_TOAST(pg_dblink, 9383, 9384);

DECLARE_UNIQUE_INDEX_PKEY(pg_dblink_oid_index, 9385, DbLinkOidIndexId, pg_dblink, btree(oid oid_ops));
DECLARE_UNIQUE_INDEX(pg_dblink_name_index, 9386, DbLinkNameIndexId, pg_dblink, btree(dblname name_ops));

MAKE_SYSCACHE(DBLINKOID, pg_dblink_oid_index, 1);
MAKE_SYSCACHE(DBLINKNAME, pg_dblink_name_index, 1);

#endif							/* PG_DBLINK_H */
