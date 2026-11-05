-- 비공개 스키마와 글자 규칙 함수 (data-model.md 11장 14번, Q-012·Q-034·Q-048, M-38)
--
-- 앱(app/lib/shared/domain/text_length.dart)과 같은 규칙으로 이름을 정리·검사한다.
-- - 보이지 않는 문자 삭제: 유니코드 Cf 전체 + U+034F·U+115F·U+1160·U+2800·U+3164·U+FFA0.
--   단 이모지 사이의 ZWJ, 검은 깃발 뒤 태그 묶음은 남긴다.
-- - 공백 정리: Dart String.trim() 과 RegExp \s 와 같은 문자 집합.
-- - 보이는 글자(grapheme) 수: Postgres는 셀 수 없으므로 코드 포인트 상한(글자 상한 × 8)만 검사한다.
--   기본 로고 글자(앞 두 글자)는 근사 grapheme 분리(private.grapheme_starts)로 만든다.
--
-- 유니코드 범위 표는 Dart RegExp(unicode: true)의 \p{Cf}, \p{Extended_Pictographic},
-- \p{Grapheme_Extend}+\p{Emoji_Modifier}, \p{Mc} 에서 생성했다 (Flutter 3.44.1 / Dart 3.12.1).

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
-- 권한 규칙(RLS)과 검사 조건이 이 스키마의 함수를 부르므로 로그인 사용자에게 사용 권한만 준다.
-- private 스키마는 API(PostgREST)에 노출하지 않는다.
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- 코드 포인트 범위 검사
-- ---------------------------------------------------------------------------

-- p_ranges = {시작1, 끝1, 시작2, 끝2, ...} (오름차순, 겹침 없음). 이진 탐색.
create function private.cp_in(p_cp int, p_ranges int[])
returns boolean
language plpgsql
immutable strict parallel safe
set search_path = ''
as $$
declare
  lo int := 1;
  hi int := coalesce(array_length(p_ranges, 1), 0) / 2;
  mid int;
begin
  while lo <= hi loop
    mid := (lo + hi) / 2;
    if p_cp < p_ranges[2 * mid - 1] then
      hi := mid - 1;
    elsif p_cp > p_ranges[2 * mid] then
      lo := mid + 1;
    else
      return true;
    end if;
  end loop;
  return false;
end;
$$;

create function private.is_cf(p_cp int)
returns boolean language sql immutable strict parallel safe set search_path = ''
as $$ select private.cp_in(p_cp, '{
    173,173,1536,1541,1564,1564,1757,1757,1807,1807,2192,2193,2274,2274,6158,6158,
    8203,8207,8234,8238,8288,8292,8294,8303,65279,65279,65529,65531,69821,69821,69837,69837,
    78896,78911,113824,113827,119155,119162,917505,917505,917536,917631
  }'::int[]) $$;

create function private.is_ext_pict(p_cp int)
returns boolean language sql immutable strict parallel safe set search_path = ''
as $$ select private.cp_in(p_cp, '{
    169,169,174,174,8252,8252,8265,8265,8482,8482,8505,8505,8596,8601,8617,8618,
    8986,8987,9000,9000,9096,9096,9167,9167,9193,9203,9208,9210,9410,9410,9642,9643,
    9654,9654,9664,9664,9723,9726,9728,9733,9735,9746,9748,9861,9872,9989,9992,10002,
    10004,10004,10006,10006,10013,10013,10017,10017,10024,10024,10035,10036,10052,10052,10055,10055,
    10060,10060,10062,10062,10067,10069,10071,10071,10083,10087,10133,10135,10145,10145,10160,10160,
    10175,10175,10548,10549,11013,11015,11035,11036,11088,11088,11093,11093,12336,12336,12349,12349,
    12951,12951,12953,12953,126976,127231,127245,127247,127279,127279,127340,127345,127358,127359,127374,127374,
    127377,127386,127405,127461,127489,127503,127514,127514,127535,127535,127538,127546,127548,127551,127561,127994,
    128000,128317,128326,128591,128640,128767,128884,128895,128981,129023,129036,129039,129096,129103,129114,129119,
    129160,129167,129198,129279,129292,129338,129340,129349,129351,129791,130048,131069
  }'::int[]) $$;

-- Grapheme_Extend ∪ Emoji_Modifier (UAX #29 의 Extend)
create function private.is_gc_extend(p_cp int)
returns boolean language sql immutable strict parallel safe set search_path = ''
as $$ select private.cp_in(p_cp, '{
    768,879,1155,1161,1425,1469,1471,1471,1473,1474,1476,1477,1479,1479,1552,1562,
    1611,1631,1648,1648,1750,1756,1759,1764,1767,1768,1770,1773,1809,1809,1840,1866,
    1958,1968,2027,2035,2045,2045,2070,2073,2075,2083,2085,2087,2089,2093,2137,2139,
    2199,2207,2250,2273,2275,2306,2362,2362,2364,2364,2369,2376,2381,2381,2385,2391,
    2402,2403,2433,2433,2492,2492,2494,2494,2497,2500,2509,2509,2519,2519,2530,2531,
    2558,2558,2561,2562,2620,2620,2625,2626,2631,2632,2635,2637,2641,2641,2672,2673,
    2677,2677,2689,2690,2748,2748,2753,2757,2759,2760,2765,2765,2786,2787,2810,2815,
    2817,2817,2876,2876,2878,2879,2881,2884,2893,2893,2901,2903,2914,2915,2946,2946,
    3006,3006,3008,3008,3021,3021,3031,3031,3072,3072,3076,3076,3132,3132,3134,3136,
    3142,3144,3146,3149,3157,3158,3170,3171,3201,3201,3260,3260,3263,3264,3266,3266,
    3270,3272,3274,3277,3285,3286,3298,3299,3328,3329,3387,3388,3390,3390,3393,3396,
    3405,3405,3415,3415,3426,3427,3457,3457,3530,3530,3535,3535,3538,3540,3542,3542,
    3551,3551,3633,3633,3636,3642,3655,3662,3761,3761,3764,3772,3784,3790,3864,3865,
    3893,3893,3895,3895,3897,3897,3953,3966,3968,3972,3974,3975,3981,3991,3993,4028,
    4038,4038,4141,4144,4146,4151,4153,4154,4157,4158,4184,4185,4190,4192,4209,4212,
    4226,4226,4229,4230,4237,4237,4253,4253,4957,4959,5906,5909,5938,5940,5970,5971,
    6002,6003,6068,6069,6071,6077,6086,6086,6089,6099,6109,6109,6155,6157,6159,6159,
    6277,6278,6313,6313,6432,6434,6439,6440,6450,6450,6457,6459,6679,6680,6683,6683,
    6742,6742,6744,6750,6752,6752,6754,6754,6757,6764,6771,6780,6783,6783,6832,6862,
    6912,6915,6964,6973,6978,6980,7019,7027,7040,7041,7074,7077,7080,7085,7142,7142,
    7144,7145,7149,7149,7151,7155,7212,7219,7222,7223,7376,7378,7380,7392,7394,7400,
    7405,7405,7412,7412,7416,7417,7616,7679,8204,8204,8400,8432,11503,11505,11647,11647,
    11744,11775,12330,12335,12441,12442,42607,42610,42612,42621,42654,42655,42736,42737,43010,43010,
    43014,43014,43019,43019,43045,43046,43052,43052,43204,43205,43232,43249,43263,43263,43302,43309,
    43335,43345,43347,43347,43392,43394,43443,43443,43446,43449,43452,43453,43456,43456,43493,43493,
    43561,43566,43569,43570,43573,43574,43587,43587,43596,43596,43644,43644,43696,43696,43698,43700,
    43703,43704,43710,43711,43713,43713,43756,43757,43766,43766,44005,44005,44008,44008,44013,44013,
    64286,64286,65024,65039,65056,65071,65438,65439,66045,66045,66272,66272,66422,66426,68097,68099,
    68101,68102,68108,68111,68152,68154,68159,68159,68325,68326,68900,68903,68969,68973,69291,69292,
    69372,69375,69446,69456,69506,69509,69633,69633,69688,69702,69744,69744,69747,69748,69759,69761,
    69811,69814,69817,69818,69826,69826,69888,69890,69927,69931,69933,69940,70003,70003,70016,70017,
    70070,70078,70080,70080,70089,70092,70095,70095,70191,70193,70196,70199,70206,70206,70209,70209,
    70367,70367,70371,70378,70400,70401,70459,70460,70462,70462,70464,70464,70477,70477,70487,70487,
    70502,70508,70512,70516,70584,70584,70587,70592,70594,70594,70597,70597,70599,70601,70606,70608,
    70610,70610,70625,70626,70712,70719,70722,70724,70726,70726,70750,70750,70832,70832,70835,70840,
    70842,70842,70845,70845,70847,70848,70850,70851,71087,71087,71090,71093,71100,71101,71103,71104,
    71132,71133,71219,71226,71229,71229,71231,71232,71339,71339,71341,71341,71344,71351,71453,71453,
    71455,71455,71458,71461,71463,71467,71727,71735,71737,71738,71984,71984,71995,71998,72003,72003,
    72148,72151,72154,72155,72160,72160,72193,72202,72243,72248,72251,72254,72263,72263,72273,72278,
    72281,72283,72330,72342,72344,72345,72752,72758,72760,72765,72767,72767,72850,72871,72874,72880,
    72882,72883,72885,72886,73009,73014,73018,73018,73020,73021,73023,73029,73031,73031,73104,73105,
    73109,73109,73111,73111,73459,73460,73472,73473,73526,73530,73536,73538,73562,73562,78912,78912,
    78919,78933,90398,90409,90413,90415,92912,92916,92976,92982,94031,94031,94095,94098,94180,94180,
    94192,94193,113821,113822,118528,118573,118576,118598,119141,119145,119149,119154,119163,119170,119173,119179,
    119210,119213,119362,119364,121344,121398,121403,121452,121461,121461,121476,121476,121499,121503,121505,121519,
    122880,122886,122888,122904,122907,122913,122915,122916,122918,122922,123023,123023,123184,123190,123566,123566,
    123628,123631,124140,124143,124398,124399,125136,125142,125252,125258,127995,127999,917536,917631,917760,917999
  }'::int[]) $$;

-- Mc + U+0E33·U+0EB3 (UAX #29 SpacingMark 근사)
create function private.is_spacing_mark(p_cp int)
returns boolean language sql immutable strict parallel safe set search_path = ''
as $$ select p_cp in (3635, 3763) or private.cp_in(p_cp, '{
    2307,2307,2363,2363,2366,2368,2377,2380,2382,2383,2434,2435,2494,2496,2503,2504,
    2507,2508,2519,2519,2563,2563,2622,2624,2691,2691,2750,2752,2761,2761,2763,2764,
    2818,2819,2878,2878,2880,2880,2887,2888,2891,2892,2903,2903,3006,3007,3009,3010,
    3014,3016,3018,3020,3031,3031,3073,3075,3137,3140,3202,3203,3262,3262,3264,3268,
    3271,3272,3274,3275,3285,3286,3315,3315,3330,3331,3390,3392,3398,3400,3402,3404,
    3415,3415,3458,3459,3535,3537,3544,3551,3570,3571,3902,3903,3967,3967,4139,4140,
    4145,4145,4152,4152,4155,4156,4182,4183,4194,4196,4199,4205,4227,4228,4231,4236,
    4239,4239,4250,4252,5909,5909,5940,5940,6070,6070,6078,6085,6087,6088,6435,6438,
    6441,6443,6448,6449,6451,6456,6681,6682,6741,6741,6743,6743,6753,6753,6755,6756,
    6765,6770,6916,6916,6965,6965,6971,6971,6973,6977,6979,6980,7042,7042,7073,7073,
    7078,7079,7082,7082,7143,7143,7146,7148,7150,7150,7154,7155,7204,7211,7220,7221,
    7393,7393,7415,7415,12334,12335,43043,43044,43047,43047,43136,43137,43188,43203,43346,43347,
    43395,43395,43444,43445,43450,43451,43454,43456,43567,43568,43571,43572,43597,43597,43643,43643,
    43645,43645,43755,43755,43758,43759,43765,43765,44003,44004,44006,44007,44009,44010,44012,44012,
    69632,69632,69634,69634,69762,69762,69808,69810,69815,69816,69932,69932,69957,69958,70018,70018,
    70067,70069,70079,70080,70094,70094,70188,70190,70194,70195,70197,70197,70368,70370,70402,70403,
    70462,70463,70465,70468,70471,70472,70475,70477,70487,70487,70498,70499,70584,70586,70594,70594,
    70597,70597,70599,70602,70604,70605,70607,70607,70709,70711,70720,70721,70725,70725,70832,70834,
    70841,70841,70843,70846,70849,70849,71087,71089,71096,71099,71102,71102,71216,71218,71227,71228,
    71230,71230,71340,71340,71342,71343,71350,71350,71454,71454,71456,71457,71462,71462,71724,71726,
    71736,71736,71984,71989,71991,71992,71997,71997,72000,72000,72002,72002,72145,72147,72156,72159,
    72164,72164,72249,72249,72279,72280,72343,72343,72751,72751,72766,72766,72873,72873,72881,72881,
    72884,72884,73098,73102,73107,73108,73110,73110,73461,73462,73475,73475,73524,73525,73534,73535,
    73537,73537,90410,90412,94033,94087,94192,94193,119141,119142,119149,119154
  }'::int[]) $$;

-- 문자열 → 코드 포인트 배열
create function private.code_points(p_text text)
returns int[]
language sql immutable strict parallel safe set search_path = ''
as $$
  select coalesce(array_agg(ascii(c) order by n), '{}'::int[])
  from unnest(string_to_array(p_text, null)) with ordinality as u(c, n)
$$;

-- ---------------------------------------------------------------------------
-- 보이지 않는 문자 삭제 (text_length.dart removeInvisibleChars 와 같은 규칙)
-- ---------------------------------------------------------------------------
create function private.remove_invisible_chars(p_text text)
returns text
language plpgsql
immutable strict parallel safe
set search_path = ''
as $$
declare
  a int[] := private.code_points(p_text);
  n int := coalesce(array_length(a, 1), 0);
  i int := 1;
  j int;
  k int;
  cp int;
  result text := '';
begin
  while i <= n loop
    cp := a[i];

    -- 1) 검은 깃발 + 태그 문자열 + 취소 태그: 지역 깃발 이모지로 그대로 둔다.
    if cp = 127988 then  -- U+1F3F4
      j := i + 1;
      while j <= n and a[j] between 917536 and 917630 loop  -- U+E0020..U+E007E
        j := j + 1;
      end loop;
      if j > i + 1 and j <= n and a[j] = 917631 then  -- U+E007F
        for k in i..j loop
          result := result || chr(a[k]);
        end loop;
        i := j + 1;
        continue;
      end if;
      result := result || chr(cp);
      i := i + 1;
      continue;
    end if;

    -- 2) 이모지(+변형 선택자·피부색) 뒤, 이모지 앞의 ZWJ 만 남긴다.
    if cp = 8205 then  -- U+200D
      j := i - 1;
      while j >= 1 and (a[j] in (65038, 65039) or a[j] between 127995 and 127999) loop
        j := j - 1;
      end loop;
      if j >= 1 and private.is_ext_pict(a[j]) and i < n and private.is_ext_pict(a[i + 1]) then
        result := result || chr(cp);
      end if;
      i := i + 1;
      continue;
    end if;

    -- 3) 나머지 보이지 않는 문자는 지운다.
    if not (private.is_cf(cp) or cp in (847, 4447, 4448, 10240, 12644, 65440)) then
      result := result || chr(cp);
    end if;
    i := i + 1;
  end loop;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 공백 정리
-- ---------------------------------------------------------------------------

-- Dart String.trim() 과 같은 문자 집합으로 앞뒤 공백 제거.
create function private.normalize_input(p_text text)
returns text
language sql immutable strict parallel safe set search_path = ''
as $$
  select btrim(
    p_text,
    E'\u0009\u000A\u000B\u000C\u000D \u0085                 　﻿'
  )
$$;

-- 한 줄 이름 정리 (text_length.dart normalizeSingleLineName):
-- 보이지 않는 문자 삭제 → 앞뒤 공백 제거 → 줄바꿈이 아닌 공백 연속을 띄어쓰기 하나로.
create function private.normalize_single_line_name(p_text text)
returns text
language sql immutable strict parallel safe set search_path = ''
as $$
  select regexp_replace(
    private.normalize_input(private.remove_invisible_chars(p_text)),
    '[\u0009\u000B\u000C    -   　﻿]+',
    ' ',
    'g'
  )
$$;

-- 모든 공백 삭제 (text_length.dart removeWhitespace, Dart RegExp \s 집합).
create function private.remove_whitespace(p_text text)
returns text
language sql immutable strict parallel safe set search_path = ''
as $$
  select regexp_replace(
    p_text,
    '[\u0009-\u000D    -     　﻿]',
    '',
    'g'
  )
$$;

-- 줄바꿈·제어 문자가 있는지.
create function private.has_control_chars(p_text text)
returns boolean
language sql immutable strict parallel safe set search_path = ''
as $$ select p_text ~ '[\u0001-\u001F\u007F-\u009F  ]' $$;

-- 한 줄 이름(팀 이름·팀에서 쓸 이름·로고 글자) 저장 검사 (11장 14번 a~f).
-- 정리 규칙을 다시 적용해도 그대로인지(= 이미 정리됨)로 앞뒤 공백·연속 공백·보이지 않는 문자를 함께 본다.
create function private.is_valid_single_line_name(p_text text, p_max_chars int)
returns boolean
language sql immutable parallel safe set search_path = ''
as $$
  select p_text is not null
    and p_text <> ''
    and char_length(p_text) <= p_max_chars * 8
    and not private.has_control_chars(p_text)
    and p_text = private.normalize_single_line_name(p_text)
$$;

-- 한 줄 글(자기소개·메모) 저장 검사 (11장 14번 a~d).
create function private.is_valid_single_line_text(p_text text, p_max_chars int)
returns boolean
language sql immutable parallel safe set search_path = ''
as $$
  select p_text is not null
    and p_text <> ''
    and char_length(p_text) <= p_max_chars * 8
    and not private.has_control_chars(p_text)
    and p_text = private.normalize_input(p_text)
$$;

-- ---------------------------------------------------------------------------
-- 보이는 글자(grapheme) 근사 분리 — 기본 로고 글자(앞 두 글자, Q-013) 계산용
--
-- UAX #29 규칙 중 GB3~GB5, GB6~GB8(한글 자모), GB9(Extend·ZWJ), GB9a(SpacingMark≈Mc),
-- GB11(이모지 ZWJ 묶음), GB12·GB13(국기)을 따른다. Prepend(GB9b)·인도계 결합(GB9c)은 생략.
-- 이름은 보이지 않는 문자·공백이 이미 정리된 뒤라 실제 이름에서는 앱(characters 패키지)과 같게 나온다.
-- ---------------------------------------------------------------------------
create function private.grapheme_starts(p_text text)
returns int[]
language plpgsql
immutable strict parallel safe
set search_path = ''
as $$
declare
  a int[] := private.code_points(p_text);
  n int := coalesce(array_length(a, 1), 0);
  starts int[] := '{}';
  i int;
  k int;
  p int;
  c int;
  ph text;
  ch text;
  ri_run int;
  joined boolean;
begin
  if n = 0 then
    return starts;
  end if;
  starts := array[1];
  for i in 2..n loop
    p := a[i - 1];
    c := a[i];
    joined := false;

    ph := case
      when p between 4352 and 4447 or p between 43360 and 43388 then 'L'
      when p between 4448 and 4519 or p between 55216 and 55238 then 'V'
      when p between 4520 and 4607 or p between 55243 and 55291 then 'T'
      when p between 44032 and 55203 then case when (p - 44032) % 28 = 0 then 'LV' else 'LVT' end
    end;
    ch := case
      when c between 4352 and 4447 or c between 43360 and 43388 then 'L'
      when c between 4448 and 4519 or c between 55216 and 55238 then 'V'
      when c between 4520 and 4607 or c between 55243 and 55291 then 'T'
      when c between 44032 and 55203 then case when (c - 44032) % 28 = 0 then 'LV' else 'LVT' end
    end;

    if p = 13 and c = 10 then
      joined := true;                                             -- GB3
    elsif (p < 32 or p between 127 and 159 or p in (8232, 8233)
           or (private.is_cf(p) and p not in (8204, 8205) and not private.is_gc_extend(p)))
       or (c < 32 or c between 127 and 159 or c in (8232, 8233)
           or (private.is_cf(c) and c not in (8204, 8205) and not private.is_gc_extend(c))) then
      joined := false;                                            -- GB4, GB5
    elsif (ph = 'L' and ch in ('L', 'V', 'LV', 'LVT'))
       or (ph in ('LV', 'V') and ch in ('V', 'T'))
       or (ph in ('LVT', 'T') and ch = 'T') then
      joined := true;                                             -- GB6~GB8
    elsif private.is_gc_extend(c) or c = 8205 or private.is_spacing_mark(c) then
      joined := true;                                             -- GB9, GB9a
    elsif p = 8205 and private.is_ext_pict(c) then
      k := i - 2;                                                 -- GB11
      while k >= 1 and private.is_gc_extend(a[k]) loop
        k := k - 1;
      end loop;
      joined := k >= 1 and private.is_ext_pict(a[k]);
    elsif p between 127462 and 127487 and c between 127462 and 127487 then
      ri_run := 0;                                                -- GB12, GB13
      k := i - 1;
      while k >= 1 and a[k] between 127462 and 127487 loop
        ri_run := ri_run + 1;
        k := k - 1;
      end loop;
      joined := ri_run % 2 = 1;
    end if;

    if not joined then
      starts := starts || i;
    end if;
  end loop;
  return starts;
end;
$$;

create function private.grapheme_count(p_text text)
returns int
language sql immutable strict parallel safe set search_path = ''
as $$ select coalesce(array_length(private.grapheme_starts(p_text), 1), 0) $$;

-- 앞에서 p_count 개의 보이는 글자 (text_length.dart takeChars).
create function private.take_graphemes(p_text text, p_count int)
returns text
language plpgsql
immutable strict parallel safe
set search_path = ''
as $$
declare
  s int[] := private.grapheme_starts(p_text);
begin
  if coalesce(array_length(s, 1), 0) <= p_count then
    return p_text;
  end if;
  return substr(p_text, 1, s[p_count + 1] - 1);
end;
$$;

-- 기본 로고 글자 (Q-013, team_validation.dart defaultLogoText):
-- 보이지 않는 문자와 모든 공백을 뺀 앞 두 글자. 영문 대소문자는 그대로.
create function private.default_logo_text(p_team_name text)
returns text
language sql immutable strict parallel safe set search_path = ''
as $$
  select private.take_graphemes(
    private.remove_whitespace(private.remove_invisible_chars(p_team_name)),
    2
  )
$$;

-- 실행 권한: 기본(PUBLIC) 회수 후, 검사 조건·트리거가 쓰는 순수 함수만 로그인 사용자에게.
revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;
