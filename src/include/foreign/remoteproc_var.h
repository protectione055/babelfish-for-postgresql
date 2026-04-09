#ifndef REMOTEPROC_VAR_H
#define REMOTEPROC_VAR_H

#include "postgres.h"

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
}			RemoteProcVarHook;

typedef struct RemoteProcOutputValue
{
	int			arg_index;
	bool		is_return_status;
	Oid			valtype;
	int32		valtypmod;
	Datum		value;
	bool		isnull;
}			RemoteProcOutputValue;

#endif							/* REMOTEPROC_VAR_H */
