DO BEGIN

	DECLARE itemcode NVARCHAR(50) = 'SA3032001';
	
	SELECT
		T1."ItemCode",
		T1."POS_ID",
		T1."POS_TEXT",
		T1."SortId",
		T1."AG_ID",
		T1."APLATZ_ID",
		T1."UDF1",
		T1."MASTER_POS_ID"
	FROM
		"BEAS_APL_HEADER" T0
	INNER JOIN
		"BEAS_APL" T1 ON T0."ItemCode" = T1."ItemCode"
	WHERE
		T0."ItemCode" = :itemcode
	ORDER BY
		T1."POS_ID";

END;