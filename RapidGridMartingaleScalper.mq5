//+------------------------------------------------------------------+
//| RAPID GRID MARTINGALE SCALPER V1                                 |
//| MT5 - XAUUSD M1                                                  |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
CTrade trade;

//======================
// GENERAL SETTINGS
//======================
input group "=== GENERAL ==="
input ulong MagicNumber = 19112026;
input int EntryIntervalSeconds = 5;
input int MaxPositions = 10;
input int MaxSpread = 50;
input int Slippage = 30;

//======================
// LOT SETTINGS
//======================
input group "=== MARTINGALE ==="
input double StartLot = 0.01;
input double Multiplier = 1.5;
input int MaxMartingaleLevel = 7;

//======================
// GRID SETTINGS
//======================
input group "=== GRID ==="
input int GridDistance = 300;
input bool EnableGrid = true;

//======================
// DIRECTION
//======================
enum ENUM_DIRECTION
{
   AUTO_EMA = 0,
   BUY_ONLY = 1,
   SELL_ONLY = 2
};

input group "=== DIRECTION ==="
input ENUM_DIRECTION DirectionMode = AUTO_EMA;
input int FastEMA = 20;
input int SlowEMA = 50;

//======================
// BASKET SETTINGS
//======================
input group "=== BASKET PROFIT ==="
input double BasketTP = 3.0;
input double BasketSL = 20.0;

//======================
// TRAILING
//======================
input group "=== TRAILING ==="
input bool EnableTrailing = true;
input double TrailingStart = 2.0;
input double TrailingStop = 1.0;

//======================
// GLOBAL
//======================
int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;

datetime lastEntryTime = 0;
double highestBasketProfit = 0;

int CurrentSpread()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}

//======================
// LOT CALCULATION
//======================
double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step + 0.0000001) * step;

   int digits = 2;
   if(step == 0.001) digits = 3;
   if(step == 0.1) digits = 1;

   return NormalizeDouble(lot, digits);
}

//======================
// POSITION COUNT
//======================
int CountPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      count++;
   }

   return count;
}

//======================
// BASKET PROFIT
//======================
double BasketProfit()
{
   double profit = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      profit += PositionGetDouble(POSITION_PROFIT);
      profit += PositionGetDouble(POSITION_SWAP);
   }

   return profit;
}

//======================
// LAST ENTRY PRICE
//======================
double LastEntryPrice()
{
   double price = 0;
   long latestTime = -1;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long time = PositionGetInteger(POSITION_TIME_MSC);

      if(time > latestTime)
      {
         latestTime = time;
         price = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   return price;
}

//======================
// POSITION DIRECTION
//======================
int GetDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY) return 1;
      if(type == POSITION_TYPE_SELL) return -1;
   }

   return 0;
}

//======================
// AUTO SIGNAL
//======================
int GetSignal()
{
   if(DirectionMode == BUY_ONLY) return 1;
   if(DirectionMode == SELL_ONLY) return -1;

   double fast[1], slow[1];

   if(CopyBuffer(fastHandle, 0, 0, 1, fast) <= 0)
      return 0;

   if(CopyBuffer(slowHandle, 0, 0, 1, slow) <= 0)
      return 0;

   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;

   return 0;
}

//======================
// CLOSE ALL
//======================
void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      trade.PositionClose(ticket);
   }
}

//======================
// OPEN TRADE
//======================
bool OpenTrade(int direction, int level)
{
   double lot = StartLot * MathPow(Multiplier, level);
   lot = NormalizeLot(lot);

   bool result = false;

   if(direction == 1)
      result = trade.Buy(lot, _Symbol, 0, 0, 0, "RapidGrid BUY");

   if(direction == -1)
      result = trade.Sell(lot, _Symbol, 0, 0, 0, "RapidGrid SELL");

   if(result && trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      lastEntryTime = TimeCurrent();
      Print("ENTRY OK | Level: ", level, " | Lot: ", lot);
      return true;
   }

   Print("ENTRY FAILED: ", trade.ResultRetcodeDescription());
   return false;
}

//======================
// BASKET MANAGEMENT
//======================
bool ManageBasket()
{
   int count = CountPositions();

   if(count == 0)
   {
      highestBasketProfit = 0;
      return false;
   }

   double profit = BasketProfit();

   // STOP LOSS
   if(BasketSL > 0 && profit <= -BasketSL)
   {
      Print("BASKET STOP LOSS");
      CloseAll();
      return true;
   }

   // TAKE PROFIT
   if(BasketTP > 0 && profit >= BasketTP)
   {
      Print("BASKET TAKE PROFIT");
      CloseAll();
      return true;
   }

   // TRAILING PROFIT
   if(EnableTrailing)
   {
      if(profit >= TrailingStart)
      {
         if(profit > highestBasketProfit)
            highestBasketProfit = profit;

         if(profit <= highestBasketProfit - TrailingStop)
         {
            Print("BASKET TRAILING CLOSED");
            CloseAll();
            return true;
         }
      }
   }

   return false;
}

//======================
// ENTRY ENGINE
//======================
void ProcessEntry()
{
   int count = CountPositions();

   if(count >= MaxPositions)
      return;

   if(CurrentSpread() > MaxSpread)
      return;

   if(TimeCurrent() - lastEntryTime < EntryIntervalSeconds)
      return;

   int direction = GetDirection();

   // INITIAL ENTRY
   if(count == 0)
   {
      direction = GetSignal();

      if(direction == 0)
         return;

      OpenTrade(direction, 0);
      return;
   }

   // GRID RECOVERY
   if(!EnableGrid)
      return;

   if(count > MaxMartingaleLevel)
      return;

   double lastPrice = LastEntryPrice();

   if(lastPrice <= 0)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool shouldEnter = false;

   if(direction == 1)
   {
      if(bid <= lastPrice - GridDistance * _Point)
         shouldEnter = true;
   }

   if(direction == -1)
   {
      if(ask >= lastPrice + GridDistance * _Point)
         shouldEnter = true;
   }

   if(shouldEnter)
      OpenTrade(direction, count);
}

//======================
// DASHBOARD
//======================
void Dashboard()
{
   int count = CountPositions();
   double profit = BasketProfit();

   string direction = "WAIT";

   if(count > 0)
   {
      direction = GetDirection() == 1 ? "BUY" : "SELL";
   }
   else
   {
      int signal = GetSignal();

      if(signal == 1) direction = "BUY SIGNAL";
      if(signal == -1) direction = "SELL SIGNAL";
   }

   string panel =
      "\n===== RAPID GRID MARTINGALE V1 =====\n"
      "Symbol       : " + _Symbol + "\n"
      "Direction    : " + direction + "\n"
      "Positions    : " + IntegerToString(count) + "\n"
      "Spread       : " + IntegerToString(CurrentSpread()) + "\n"
      "Basket P/L   : " + DoubleToString(profit, 2) + "\n"
      "Interval     : " + IntegerToString(EntryIntervalSeconds) + " sec\n"
      "Max Position : " + IntegerToString(MaxPositions) + "\n"
      "===================================";

   Comment(panel);
}

//======================
// INITIALIZATION
//======================
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   fastHandle = iMA(_Symbol, PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE)
   {
      Print("EMA INITIALIZATION FAILED");
      return INIT_FAILED;
   }

   EventSetTimer(1);

   Print("RAPID GRID MARTINGALE STARTED");

   return INIT_SUCCEEDED;
}

//======================
// TIMER
//======================
void OnTimer()
{
   ManageBasket();

   ProcessEntry();

   Dashboard();
}

//======================
// TICK
//======================
void OnTick()
{
   ManageBasket();
}

//======================
// DEINITIALIZATION
//======================
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(fastHandle != INVALID_HANDLE)
      IndicatorRelease(fastHandle);

   if(slowHandle != INVALID_HANDLE)
      IndicatorRelease(slowHandle);

   Comment("");
}
//+------------------------------------------------------------------+
