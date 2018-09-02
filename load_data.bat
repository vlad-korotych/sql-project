psql -U postgres -c "drop table if exists bankacc;"
psql -U postgres -c "drop table if exists collateral;"
psql -U postgres -c "drop table if exists market_risk;"
psql -U postgres -c "drop table if exists positions;"

psql -U postgres -c "create table bankacc (bankaccid varchar(5), typ varchar(3), firmid varchar(12));"
psql -U postgres -c "\copy bankacc from '.\data\bankacc.csv' delimiter ',' csv header"

psql -U postgres -c "create table collateral (bankaccid varchar(5), currencyid varchar(3), volume decimal);"
psql -U postgres -c "\copy collateral from '.\data\collateral.csv' delimiter ',' csv header"

psql -U postgres -c "create table market_risk (asset varchar(3), limit_con decimal, discount decimal, price_clean decimal);"
psql -U postgres -c "\copy market_risk from '.\data\market_risk.csv' delimiter ',' csv header"

psql -U postgres -c "create table positions (bankaccid varchar(5), currencyid varchar(3), settledate date, volume decimal);"
psql -U postgres -c "\copy positions from '.\data\positions.csv' delimiter ',' csv header"