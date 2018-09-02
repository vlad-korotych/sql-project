-- 1. Получаем список фирм
select distinct
  firmid
from bankacc
;

-- 2. Получаем расчетные кода, допустившие технический овердрафт
select
  *
from collateral
where volume < 0
;

-- 3. Узнаем тип расчетных кодов, допустивших технический овердрафт, и к каким фирмам они принадлежат
select
  *
from collateral c
join bankacc b on b.bankaccid = c.bankaccid
where c.volume < 0
;

-- 4. Получаем суммарную позицию в разрезе расчетный код/актив
select
  bankaccid,
  currencyid,
  sum(volume) as volume
from positions
group by bankaccid, currencyid
;

-- Создаем представление на основе запроса 3
create or replace view v_sum_positions
as
select
  bankaccid,
  currencyid,
  sum(volume) as volume
from positions
group by bankaccid, currencyid
;

-- 5. Получаем суммарную позицию в разрезе фирма/день/актив
select
  b.firmid,
  p.settledate,
  p.currencyid,
  sum(p.volume)
from positions p
join bankacc b on b.bankaccid = p.bankaccid
group by b.firmid, p.settledate, p.currencyid
order by b.firmid, p.settledate
;

-- 6. Получем переоценку залоговых средств по текущей цене
select
  b.firmid,
  sum(c.volume * r.price_clean) as value
from collateral c
join (
  select distinct
    asset,
    price_clean
  from market_risk
) r on c.currencyid = r.asset
join bankacc b on b.bankaccid = c.bankaccid
group by b.firmid
;

-- 7. Получаем нетто-позицию в разрезе расчетный код/актив
select
  coalesce(c.bankaccid, p.bankaccid) as bankaccid,
  coalesce(c.currencyid, p.currencyid) as currencyid,
  coalesce(c.volume, 0) as collateral_volume,
  coalesce(p.volume, 0) as position_volume,
  coalesce(c.volume, 0) + coalesce(p.volume, 0) as net_position
from collateral c
full outer join v_sum_positions p on p.bankaccid = c.bankaccid and p.currencyid = c.currencyid
order by bankaccid
;

-- Создаем представление на основе запроса 7
create or replace view v_net_position
as
select
  coalesce(c.bankaccid, p.bankaccid) as bankaccid,
  coalesce(c.currencyid, p.currencyid) as currencyid,
  coalesce(c.volume, 0) as collateral_volume,
  coalesce(p.volume, 0) as position_volume,
  coalesce(c.volume, 0) + coalesce(p.volume, 0) as net_position
from collateral c
full outer join v_sum_positions p on p.bankaccid = c.bankaccid and p.currencyid = c.currencyid
order by bankaccid
;

-- 8. Переформатируем таблицу с рыночным риском так, чтобы получить номер лимита концентрации и его обе границы
select
  row_number() over (partition by asset order by limit_con) as num,
  limit_con as limitbegin,
  lead(limit_con) over (partition by asset order by limit_con) as limitend,
  discount,
  price_clean
from market_risk
;

-- Создаем представление на основе запроса 8
create or replace view v_pricerange
as
select
  row_number() over (partition by asset order by limit_con) as num,
  limit_con as limitbegin,
  lead(limit_con) over (partition by asset order by limit_con) as limitend,
  asset,
  discount,
  price_clean
from market_risk
;

 if(abs(p.netPosition)>r.limitEnd, rate*(r.limitEnd-r.limitBegin), if(abs(p.netPosition)>r.limitBegin, (abs(p.netPosition)-r.limitBegin)*rate, 0)) as marketRisk

-- 9. Вычисляем рыночный риск по лимиту концентрации
select
  p.bankaccid,
  p.currencyid,
  p.net_position,
  r.num,
  r.limitbegin,
  r.limitend,
  r.price_clean,
  r.discount,
  case
    when p.currencyid = 'RUB' then net_position
    when r.limitend is not null and abs(p.net_position) > r.limitend then (1 - r.discount) * price_clean * (r.limitend - r.limitbegin) * sign(p.net_position)
    when abs(p.net_position) > r.limitbegin then (1 - r.discount) * price_clean * (abs(p.net_position) - r.limitbegin) * sign(p.net_position)
    else 0
  end as market_risk
from v_net_position p
left join v_pricerange r on p.currencyid = r.asset
order by p.bankaccid, p.currencyid, r.num
;

-- 10. Вычисляем достаточность средств для покрытия позиций
select
  bankaccid,
  sum(market_risk) as market_risk
from (
  select
    p.bankaccid,
    case
      when p.currencyid = 'RUB' then net_position
      when r.limitend is not null and abs(p.net_position) > r.limitend then (1 - r.discount) * price_clean * (r.limitend - r.limitbegin) * sign(p.net_position)
      when abs(p.net_position) > r.limitbegin then (1 - r.discount) * price_clean * (abs(p.net_position) - r.limitbegin) * sign(p.net_position)
      else 0
    end as market_risk
  from v_net_position p
  left join v_pricerange r on p.currencyid = r.asset
) r
group by bankaccid
;