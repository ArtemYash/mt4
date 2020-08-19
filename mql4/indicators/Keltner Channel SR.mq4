/**
 * Keltner Channel SR
 *
 * A support/resistance line of only rising or only falling values formed by a Keltner channel (an ATR channel around a
 * Moving Average). The SR line changes direction when it's crossed by the Moving Average. ATR values can be smoothed by a
 * second Moving Average.
 *
 * Supported Moving Average types:
 *  � SMA  - Simple Moving Average:          equal bar weighting
 *  � LWMA - Linear Weighted Moving Average: bar weighting using a linear function
 *  � EMA  - Exponential Moving Average:     bar weighting using an exponential function
 *  � SMMA - Smoothed Moving Average:        same as EMA, it holds: SMMA(n) = EMA(2*n-1)
 */
#include <stddefines.mqh>
int   __INIT_FLAGS__[];
int __DEINIT_FLAGS__[];

////////////////////////////////////////////////////// Configuration ////////////////////////////////////////////////////////

extern string MA.Method             = "SMA* | LWMA | EMA | SMMA";
extern int    MA.Periods            = 10;                                                          // Nix: 1
extern string MA.AppliedPrice       = "Open | High | Low | Close* | Median | Typical | Weighted";  // Nix: Open
extern color  MA.Color              = CLR_NONE;

extern int    ATR.Periods           = 60;
extern double ATR.Multiplier        =  3;
extern string ATR.Smoothing.Method  = "SMA* | LWMA | EMA | SMMA";                                  // Nix: EMA
extern int    ATR.Smoothing.Periods = 1;                                                           // Nix: 10
extern color  ATR.Channel.Color     = CLR_NONE;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include <core/indicator.mqh>
#include <stdfunctions.mqh>
#include <rsfLibs.mqh>

#define MODE_MA               Bands.MODE_MA           // indicator buffer ids
#define MODE_UPPER_BAND       Bands.MODE_UPPER
#define MODE_LOWER_BAND       Bands.MODE_LOWER
#define MODE_LINE_DOWN        3
#define MODE_LINE_DOWNSTART   4
#define MODE_LINE_UP          5
#define MODE_LINE_UPSTART     6
#define MODE_ATR              7

#property indicator_chart_window
#property indicator_buffers   7                       // buffers visible in input dialog
int       terminal_buffers  = 8;                      // buffers managed by the terminal

#property indicator_color1    CLR_NONE
#property indicator_color2    CLR_NONE
#property indicator_color3    CLR_NONE
#property indicator_color4    Red
#property indicator_color5    Red
#property indicator_color6    Blue
#property indicator_color7    Blue

#property indicator_style1    STYLE_DOT
#property indicator_style2    STYLE_DOT
#property indicator_style3    STYLE_DOT
#property indicator_style4    STYLE_SOLID
#property indicator_style5    STYLE_SOLID
#property indicator_style6    STYLE_DOT
#property indicator_style7    STYLE_DOT

#property indicator_width1    1
#property indicator_width2    1
#property indicator_width3    1
#property indicator_width4    2
#property indicator_width5    2
#property indicator_width6    2
#property indicator_width7    2

double ma           [];
double atr          [];
double upperBand    [];
double lowerBand    [];
double lineUp       [];
double lineUpStart  [];
double lineDown     [];
double lineDownStart[];

int    ma1Method;
int    ma1Periods;
int    ma1AppliedPrice;

int    atrPeriods;
double atrMultiplier;
int    atrSmoothingMethod;
int    atrSmoothingPeriods;

string legendLabel;


/**
 * Initialization
 *
 * @return int - error status
 */
int onInit() {
   // validate inputs
   // MA.Method
   string sValues[], sValue = MA.Method;
   if (Explode(sValue, "*", sValues, 2) > 1) {
      int size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   ma1Method = StrToMaMethod(sValue, F_ERR_INVALID_PARAMETER);
   if (ma1Method == -1)           return(catch("onInit(1)  Invalid input parameter MA.Method: "+ DoubleQuoteStr(MA.Method), ERR_INVALID_INPUT_PARAMETER));
   MA.Method = MaMethodDescription(ma1Method);
   // MA.Periods
   if (MA.Periods < 0)            return(catch("onInit(2)  Invalid input parameter MA.Periods: "+ MA.Periods, ERR_INVALID_INPUT_PARAMETER));
   ma1Periods = ifInt(!MA.Periods, 1, MA.Periods);
   // MA.AppliedPrice
   sValue = StrToLower(MA.AppliedPrice);
   if (Explode(sValue, "*", sValues, 2) > 1) {
      size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   sValue = StrTrim(sValue);
   if (sValue == "") sValue = "close";                            // default price type
   ma1AppliedPrice = StrToPriceType(sValue, F_PARTIAL_ID|F_ERR_INVALID_PARAMETER);
   if (ma1AppliedPrice==-1 || ma1AppliedPrice > PRICE_WEIGHTED)
                                  return(catch("onInit(3)  Invalid input parameter MA.AppliedPrice: "+ DoubleQuoteStr(MA.AppliedPrice), ERR_INVALID_INPUT_PARAMETER));
   MA.AppliedPrice = PriceTypeDescription(ma1AppliedPrice);

   // ATR.Periods
   if (ATR.Periods < 1)           return(catch("onInit(4)  Invalid input parameter ATR.Periods: "+ ATR.Periods, ERR_INVALID_INPUT_PARAMETER));
   atrPeriods = ATR.Periods;
   // ATR.Multiplier
   if (ATR.Multiplier < 0)        return(catch("onInit(5)  Invalid input parameter ATR.Multiplier: "+ NumberToStr(ATR.Multiplier, ".+"), ERR_INVALID_INPUT_PARAMETER));
   atrMultiplier = ATR.Multiplier;
   // ATR.Smoothing.Method
   sValue = ATR.Smoothing.Method;
   if (Explode(sValue, "*", sValues, 2) > 1) {
      size = Explode(sValues[0], "|", sValues, NULL);
      sValue = sValues[size-1];
   }
   atrSmoothingMethod = StrToMaMethod(sValue, F_ERR_INVALID_PARAMETER);
   if (atrSmoothingMethod == -1)  return(catch("onInit(6)  Invalid input parameter ATR.Smoothing.Method: "+ DoubleQuoteStr(ATR.Smoothing.Method), ERR_INVALID_INPUT_PARAMETER));
   ATR.Smoothing.Method = MaMethodDescription(atrSmoothingMethod);
   // ATR.Smoothing.Periods
   if (ATR.Smoothing.Periods < 0) return(catch("onInit(7)  Invalid input parameter ATR.Smoothing.Periods: "+ ATR.Smoothing.Periods, ERR_INVALID_INPUT_PARAMETER));
   atrSmoothingPeriods = ifInt(!ATR.Smoothing.Periods, 1, ATR.Smoothing.Periods);

   // colors: after deserialization the terminal might turn CLR_NONE (0xFFFFFFFF) into Black (0xFF000000)
   if (MA.Color          == 0xFF000000) MA.Color          = CLR_NONE;
   if (ATR.Channel.Color == 0xFF000000) ATR.Channel.Color = CLR_NONE;

   // buffer management
   SetIndexBuffer(MODE_MA,         ma       ); SetIndexEmptyValue(MODE_MA,         0);
   SetIndexBuffer(MODE_ATR,        atr      );                                         // invisible
   SetIndexBuffer(MODE_UPPER_BAND, upperBand); SetIndexEmptyValue(MODE_UPPER_BAND, 0);
   SetIndexBuffer(MODE_LOWER_BAND, lowerBand); SetIndexEmptyValue(MODE_LOWER_BAND, 0);

   // chart legend
   if (!IsSuperContext()) {
       legendLabel = CreateLegendLabel();
       RegisterObject(legendLabel);
   }

   // names, labels and display options
   IndicatorShortName(WindowExpertName());                                                                                 // chart tooltips and context menu
   SetIndexLabel(MODE_MA,         "KCh MA"   ); if (MA.Color          == CLR_NONE) SetIndexLabel(MODE_MA,         NULL);   // chart tooltips and "Data" window
   SetIndexLabel(MODE_UPPER_BAND, "KCh Upper"); if (ATR.Channel.Color == CLR_NONE) SetIndexLabel(MODE_UPPER_BAND, NULL);
   SetIndexLabel(MODE_LOWER_BAND, "KCh Lower"); if (ATR.Channel.Color == CLR_NONE) SetIndexLabel(MODE_LOWER_BAND, NULL);
   IndicatorDigits(Digits);
   SetIndicatorOptions();



   SetIndexBuffer(MODE_LINE_UP,        lineUp       ); SetIndexEmptyValue(MODE_LINE_UP,        0); SetIndexLabel(MODE_LINE_UP,        "KCh Support");
   SetIndexBuffer(MODE_LINE_UPSTART,   lineUpStart  ); SetIndexEmptyValue(MODE_LINE_UPSTART,   0); SetIndexLabel(MODE_LINE_UPSTART,   NULL); SetIndexStyle(MODE_LINE_UPSTART,   DRAW_ARROW, EMPTY); SetIndexArrow(MODE_LINE_UPSTART,   159);
   SetIndexBuffer(MODE_LINE_DOWN,      lineDown     ); SetIndexEmptyValue(MODE_LINE_DOWN,      0); SetIndexLabel(MODE_LINE_DOWN,      "KCh Resistance");
   SetIndexBuffer(MODE_LINE_DOWNSTART, lineDownStart); SetIndexEmptyValue(MODE_LINE_DOWNSTART, 0); SetIndexLabel(MODE_LINE_DOWNSTART, NULL); SetIndexStyle(MODE_LINE_DOWNSTART, DRAW_ARROW, EMPTY); SetIndexArrow(MODE_LINE_DOWNSTART, 159);

   return(catch("onInit(4)"));
}


/**
 * Deinitialization
 *
 * @return int - error status
 */
int onDeinit() {
   RepositionLegend();
   return(catch("onDeinit(1)"));
}


/**
 * Main function
 *
 * @return int - error status
 */
int onTick() {
   // on the first tick after terminal start buffers may not yet be initialized (spurious issue)
   if (!ArraySize(ma)) return(log("onTick(1)  size(ma) = 0", SetLastError(ERS_TERMINAL_NOT_YET_READY)));

   // reset all buffers and delete garbage before doing a full recalculation
   if (!UnchangedBars) {
      ArrayInitialize(ma,            0);
      ArrayInitialize(atr,           0);
      ArrayInitialize(upperBand,     0);
      ArrayInitialize(lowerBand,     0);
      ArrayInitialize(lineUp,        0);
      ArrayInitialize(lineUpStart,   0);
      ArrayInitialize(lineDown,      0);
      ArrayInitialize(lineDownStart, 0);
      SetIndicatorOptions();
   }

   // synchronize buffers with a shifted offline chart
   if (ShiftedBars > 0) {
      ShiftIndicatorBuffer(ma,            Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(atr,           Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(upperBand,     Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(lowerBand,     Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(lineUp,        Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(lineUpStart,   Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(lineDown,      Bars, ShiftedBars, 0);
      ShiftIndicatorBuffer(lineDownStart, Bars, ShiftedBars, 0);
   }

   // recalculate changed MA values
   int initBars = ma1Periods-1;
   if (ma1Periods > 1 && (ma1Method==MODE_EMA || ma1Method==MODE_SMMA))
      initBars = Max(10, ma1Periods*3);                                    // IIR filters need at least 10 bars for initialization
   int maBars = Bars-initBars;
   int maStartBar = Min(ChangedBars, maBars) - 1;
   if (maStartBar < 0) return(catch("onTick(2)", ERR_HISTORY_INSUFFICIENT));

   for (int bar=maStartBar; bar >= 0; bar--) {
      ma[bar] = iMA(NULL, NULL, ma1Periods, 0, ma1Method, ma1AppliedPrice, bar);
   }

   // recalculate changed ATR values
   initBars = atrPeriods-1;
   int atrBars = Bars-initBars;
   int atrStartBar = Min(ChangedBars, atrBars) - 1;
   if (atrStartBar < 0) return(catch("onTick(3)", ERR_HISTORY_INSUFFICIENT));

   for (bar=atrStartBar; bar >= 0; bar--) {
      atr[bar] = iATR(NULL, NULL, atrPeriods, bar);
   }

   // recalculate changed ATR channel values
   initBars = atrSmoothingPeriods-1;
   if (atrSmoothingPeriods > 1 && (atrSmoothingMethod==MODE_EMA || atrSmoothingMethod==MODE_SMMA))
      initBars = Max(10, atrSmoothingPeriods*3);                           // IIR filters need at least 10 bars for initialization
   int channelBars = Min(maBars, atrBars);
   int channelStartBar = Min(ChangedBars, channelBars) - 1;
   if (channelStartBar < 0) return(catch("onTick(4)", ERR_HISTORY_INSUFFICIENT));

   for (bar=channelStartBar; bar >= 0; bar--) {
      double channelWidth = atrMultiplier * iMAOnArray(atr, WHOLE_ARRAY, atrSmoothingPeriods, 0, atrSmoothingMethod, bar);
      upperBand[bar] = ma[bar] + channelWidth;
      lowerBand[bar] = ma[bar] - channelWidth;
   }



   // calculate SR start bar
   initBars = ifInt(atrSmoothingMethod==MODE_EMA, Max(10, atrSmoothingPeriods*3), atrSmoothingPeriods);     // IIR filters need at least 10 bars for initialization
   int bars = atrBars-initBars;                                                     // one bar less as SR calculation looks back one bar
   int startBar = Min(ChangedBars, bars) - 1;
   if (startBar < 0) return(catch("onTick(4)", ERR_HISTORY_INSUFFICIENT));

   double prevSR = lineUp[startBar+1] + lineDown[startBar+1];
   if (!prevSR) prevSR = Open[startBar+1];

   // recalculate changed SR values
   for (int i=startBar; i >= 0; i--) {
      if (!atr[i]) continue;

      double price     = Open[i];
      double prevPrice = Open[i+1];

      if (prevPrice < prevSR) {
         if (price < prevSR) {
            lineUp  [i] = 0;
            lineDown[i] = MathMin(prevSR, upperBand[i]);
         }
         else {
            lineUp  [i] = lowerBand[i]; lineUpStart[i] = lineUp[i];
            lineDown[i] = 0;
         }
      }
      else /*prevPrice > prevSR*/{
         if (price > prevSR) {
            lineUp  [i] = MathMax(prevSR, lowerBand[i]);
            lineDown[i] = 0;
         }
         else {
            lineUp  [i] = 0;
            lineDown[i] = upperBand[i]; lineDownStart[i] = lineDown[i];
         }
      }
      prevSR = lineUp[i] + lineDown[i];
   }
   return(last_error);
}


/**
 * Workaround for various terminal bugs when setting indicator options. Usually options are set in init(). However after
 * recompilation options must be set in start() to not be ignored.
 */
void SetIndicatorOptions() {
   IndicatorBuffers(terminal_buffers);

   int drawType = ifInt(MA.Color==CLR_NONE, DRAW_NONE, DRAW_LINE);
   SetIndexStyle(MODE_MA,         drawType, EMPTY, EMPTY, MA.Color);

   drawType = ifInt(ATR.Channel.Color==CLR_NONE, DRAW_NONE, DRAW_LINE);
   SetIndexStyle(MODE_UPPER_BAND, drawType, EMPTY, EMPTY, ATR.Channel.Color);
   SetIndexStyle(MODE_LOWER_BAND, drawType, EMPTY, EMPTY, ATR.Channel.Color);
}


/**
 * Return a string representation of the input parameters (for logging purposes).
 *
 * @return string
 */
string InputsToStr() {
   return(StringConcatenate("MA.Method=",             DoubleQuoteStr(MA.Method),            ";", NL,
                            "MA.Periods=",            MA.Periods,                           ";", NL,
                            "MA.AppliedPrice=",       DoubleQuoteStr(MA.AppliedPrice),      ";", NL,
                            "MA.Color=",              ColorToStr(MA.Color),                 ";", NL,
                            "ATR.Smoothing.Method=",  DoubleQuoteStr(ATR.Smoothing.Method), ";", NL,
                            "ATR.Smoothing.Periods=", ATR.Smoothing.Periods,                ";", NL,
                            "ATR.Channel.Color=",     ColorToStr(ATR.Channel.Color),        ";")
   );
}
