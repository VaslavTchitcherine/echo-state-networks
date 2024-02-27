#!/home/egullich/forex/FinRL-Library/venv/bin/python
#
# yahoo1.py
# Calls yfinance to grab historical yahoo finance data for one symbol in a specific date range.
# Writes file with date and adjusted closing price columns to stdout.
# Note intraday only works for a date range of < 60 days.
# (https://pypi.org/project/yfinance/)
# Example:
#	yahoo1.py --start='2020-01-01' --end='2020-02-01' --sym=BTC-USD --interval=1h >/tmp/btcusd_hourly
#

import getopt
import os
import pandas as pd
import yfinance as yf
import sys

from optparse import OptionParser

# Default interval is 1 day
# Valid intervals: 1m,2m,5m,15m,30m,60m,90m,1h,1d,5d,1wk,1mo,3mo
# Note intraday only works for a date range of < 60 days.
interval = '1d'

# parse command line args
parser = OptionParser()
parser.add_option('-s', '--start', dest='start', help='start date')
parser.add_option('-e', '--end', dest='end', help='end date')
parser.add_option('-y', '--sym', dest='sym', help='ticker symbol')
parser.add_option('-i', '--interval', dest='interval', help='data interval')
(options,args) = parser.parse_args()
if options.start is None:
    error("must specify start daate with --start")
if options.end is None:
    error("must specify end daate with --end")
if options.sym is None:
    error("must specify symbol with --sym")
if options.interval:
	interval = options.interval

start_date = options.start
end_date = options.end

df = pd.DataFrame()

df = yf.download(tickers=options.sym,
        start=options.start,
        end=options.end,
        auto_adjust=True,	# adjust for splits and dividends
        actions=False,		# do not download splits and dividends
        progress=False,		# do not display progress
        interval=interval	# default is '1d', i.e. daily data
)

# reset the index, we want to use numbers as index instead of dates
df = df.reset_index()

#print(df.columns)

# convert the column names to standardized names
df.columns = ['date', 'open', 'high', 'low', 'close', 'volume']

# create day of the week column (monday = 0)
df["day"] = df["date"].dt.dayofweek

# convert date to ISO
df["date"] = df.date.apply(lambda x: x.strftime("%Y-%m-%d"))
        
# drop missing data
df = df.dropna()
df = df.reset_index(drop=True)

# retain only the date and the adjusted closing price 
###df = df.drop(['open', 'high', 'low', 'volume', 'day'], axis=1)
df = df.drop(['day'], axis=1)

# dump to csv file
df.to_csv(sys.stdout, header=False, index=False, sep=' ')
