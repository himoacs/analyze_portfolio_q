\c 150 250

/ Example command: q analyze_portfolio.q -sd 20170401 -ed 20170501

/ Load iex.q so we can use it to get market data
\l iex.q

/ Put command line args in a dictionary
args:.Q.opt .z.x

/ Benchmarks
benchmarks:`SPY`QQQ

/ If end date is not specified then set it to today's date
if[not `ed in key args;args[`ed]:string(.z.d-1)];

/ Load all the transactions into a table
transactions:("SSDFF";enlist",")0:`:transactions.csv;

/ If start date is not specified then set it to first transaction date
if[not `sd in key args;args[`sd]:string(exec min date from transactions)];

cash: exec price from transactions where sym like "cash";
transactions: select from transactions where not sym like "cash";

/initialize variables
transaction_fee: 7;

/ Get data for all securities in transactions table for last 2 years
prices:([]sym:"S"$();date:"D"$();close:"f"$());
f:{select sym, date, close from get_historical_summary[x;`2y]};
prices: prices uj raze f each benchmarks,exec distinct sym from transactions;

/ Calculate value of a portfolio for a given date
/ as_of_date: "D"$"20160813"

pf_stats:{[transactions; prices; as_of_date;cash;snap]

  as_of_date:"D"$string(as_of_date);
  
  / Check if date is a weekend, if it is then get latest weekday
  if[2>as_of_date mod 7;as_of_date:as_of_date-1+as_of_date mod 7];

  /Select transactions as of the date (remove future transactions)
  transactions:select from transactions where date<=as_of_date;

  / Take out transaction costs from cash
  cash-:transaction_fee*count transactions;

  / grouping
  transactions:select avg_price:size wavg price, total_size:sum size by sym,order_type from transactions;
  transactions:update total_cost:avg_price*total_size from transactions;

  / For any security that was sold, take its final worth and add it to cash
  cash+:exec sum(total_cost) from transactions where order_type=`sell;

  / For any security that was bought, take its cost and subtract from cash
  cash-:exec sum(total_cost) from transactions where order_type=`buy;

  / Subtract sold securities from bought securities so we are left with net
  transactions:update total_size:total_size*-1 from transactions where order_type=`sell;
  transactions:update total_size:sum total_size by sym from transactions;
  transactions:select from transactions where order_type=`buy;

  / Remove any securities that were completely sold
  transactions:select from transactions where total_size>0;

  / add close value to transactions table
  transactions: (select from transactions where order_type=`sell) uj (select from transactions where order_type=`buy) ij 1!select sym,close from prices where date=as_of_date;

  / Calculate current value
  transactions:update current_value:total_size*close from transactions;

  stock_worth: exec sum current_value from transactions;
  $[snap;:transactions;:(as_of_date;cash;stock_worth;cash+stock_worth)];
 }

/ Parse args and define start and end data for analysis
/ Generate date range (excluding weekends) to run analysis for
start_date: first "D"$args[`sd];
end_date: first "D"$args[`ed];
date_range: start_date + til (end_date - start_date);
date_range:date_range where not (date_range mod 7) in 0 1;

/ Take the result of pf_stats and put in a table
a:{pf_stats[transactions; prices; x;cash;0]} each date_range;
result:([]date:a[;0];cash:a[;1];stock_worth:a[;2];net:a[;3]);
result: select from result where stock_worth>0;

/ Add benchmarks prices to result table
q:select date,qqq:close from prices where sym=`QQQ;
s:select date,spy:close from prices where sym=`SPY;
result: result lj 1!s lj 1!q;

/ Get percent change
pct_chg:select date,net_pct_chg:100*(deltas net)%net, spy_pct_chg:100*(deltas spy)%spy, qqq_pct_chg:100*(deltas qqq)%qqq from result;
pct_chg:select from pct_chg where i>1;

/ Get latest detailed state of portfolio
snapshot: pf_stats[transactions; prices; .z.d-2;cash;1];
/ Calculate each stock's total percent change and their portfolio allocation
snapshot: update total_pct_chg:100*(current_value-total_cost)%total_cost,pct_of_portfolio:100*current_value%(exec sum current_value from snapshot) from snapshot;