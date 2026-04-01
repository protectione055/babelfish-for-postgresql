#ifndef REMOTEPROC_VAR_H
#define REMOTEPROC_VAR_H

#include "postgres.h"

/*
 * Hook for resolving and assigning local T-SQL variables in remote proc
 * utility execution paths where ParamListInfo can be unavailable.
 */
typedef struct RemoteProcVarHook
{
	bool		(*resolve_var) (const char *varname,
							Oid *vartype,
							int32 *vartypmod,
							Datum *value,
							bool *isnull,
							void **varref);
	bool		(*assign_var) (void *varref,
							Oid valtype,
							int32 valtypmod,
							Datum value,
							bool isnull);
} RemoteProcVarHook;

/*
 * Standard output payload element returned by FDW GetRemoteProcOutputs.
 * arg_index is 0-based and refers to the argument ordinal in RemoteProcStmt.
 * Return-status payloads set is_return_status and use arg_index = -1.
 */
typedef struct RemoteProcOutputValue
{
	int			arg_index;
	bool		is_return_status;
	Oid			valtype;
	int32		valtypmod;
	Datum		value;
	bool		isnull;
} RemoteProcOutputValue;

#endif							/* REMOTEPROC_VAR_H */