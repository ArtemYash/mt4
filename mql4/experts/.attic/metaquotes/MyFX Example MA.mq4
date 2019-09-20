/**
 * Auf das Framework umgestellte Version des "MetaQuotes Example MA". Die Strategie ist unver�ndert.
 */
#property copyright "(strategy unmodified)"

#include <stddefines.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern int    MA.Period = 12;
extern int    MA.Shift  =  6;
extern double Lotsize   =  0.1;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/expert.mqh>
#include <stdfunctions.mqh>
#include <rsfLibs.mqh>


bool isOpenPosition = false;
int  slippage       = 5;


/**
 * Main-Funktion
 *
 * @return int - Fehlerstatus
 */
int onTick() {
   // check current position
   if (!isOpenPosition) CheckForOpenSignal();
   else                 CheckForCloseSignal();        // Es ist maximal eine Position (Long oder Short) offen.
   return(last_error);
}


/**
 * Check for entry conditions
 */
void CheckForOpenSignal() {
   if (Volume[0] > 1)            // open positions only on BarOpen
      return;

   int ticket, oe[], oeFlags = NULL;
   static double   stopLoss    = NULL;
   static double   takeProfit  = NULL;
   static string   comment     = "";
   static datetime expiration  = NULL;
   static int      magicNumber = NULL;

   // Simple Moving Average of Bar[MA.Shift]
   double ma = iMA(NULL, NULL, MA.Period, MA.Shift, MODE_SMA, PRICE_CLOSE, 0);                              // MA[0] mit MA.Shift entspricht MA[Shift] bei Shift=0.
                                                                                                            // Mit einem SMA(12) liegt jede Bar zumindest in der N�he des
   // Bl�dsinn: Long-Signal, wenn die geschlossene Bar bullish war und ihr Body den MA gekreuzt hat         // MA, die Entry-Signale sind also praktisch zuf�llig.
   if (Open[1] < ma && Close[1] > ma) {
      ticket = OrderSendEx(Symbol(), OP_BUY, Lotsize, Ask, slippage, stopLoss, takeProfit, comment, magicNumber, expiration, Blue, oeFlags, oe);
      isOpenPosition = true;
      return;
   }

   // Bl�dsinn: Short-Signal, wenn kein Long-Signal, die letzte Bar bearish war und MA[6] innerhalb ihres Bodies liegt.
   if (Open[1] > ma && Close[1] < ma) {
      ticket = OrderSendEx(Symbol(), OP_SELL, Lotsize, Bid, slippage, stopLoss, takeProfit, comment, magicNumber, expiration, Red, oeFlags, oe);
      isOpenPosition = true;
      return;
   }
}


/**
 * Check for exit conditions                                // Da es keinen TakeProfit gibt und der fast zuf�llige Exit in der N�he des Entries
 *                                                          // wie ein kleiner StopLoss wirkt, provoziert die Strategie viele kleine Verluste.
 * Es ist maximal eine Position (Long oder Short) offen.    // Sie verh�lt sich �hnlich einer umgedrehten Scalping-Strategie, entsprechend verursachen
 */                                                         // Slippage, Spread und Geb�hren massive Schwankungen (in diesem Fall beim Verlust).
void CheckForCloseSignal() {
   if (Volume[0] > 1)                                       // close only onBarOpen
      return;

   // Simple Moving Average of MA[Shift]
   double ma = iMA(NULL, NULL, MA.Period, MA.Shift, MODE_SMA, PRICE_CLOSE, 0);

   int oe[], oeFlags = NULL;
   int orders = OrdersTotal();

   for (int i=0; i < orders; i++) {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         break;
      int ticket = OrderTicket();

      if (OrderType() == OP_BUY) {                                               // Bl�dsinn analog zum Entry-Signal
         if (Open[1] > ma) /*&&*/ if(Close[1] < ma) {
            OrderCloseEx(ticket, OrderLots(), slippage, Gold, oeFlags, oe);      // Exit-Long, wenn die letzte Bar bearisch war und MA[Shift] innerhalb ihres Bodies liegt.
            isOpenPosition = false;
         }
         break;
      }

      if (OrderType() == OP_SELL) {
         if (Open[1] < ma) /*&&*/ if (Close[1] > ma) {                           // Exit-Short, wenn die letzte Bar bullish war und MA[Shift] innerhalb ihres Bodies liegt.
            OrderCloseEx(ticket, OrderLots(), slippage, Gold, oeFlags, oe);
            isOpenPosition = false;
         }
         break;
      }
   }
   return;
}
