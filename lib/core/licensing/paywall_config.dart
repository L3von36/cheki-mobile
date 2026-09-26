/// Paywall + activation constants. THE OWNER EDITS THIS FILE with their
/// real payment details — everything the user sees on the paywall comes
/// from here, so one edit rebrands the whole flow.
library;

/// Telebirr account that receives the plan payments. Shown on the paywall.
const String kPayTelebirrNumber = '+251 98 968 0816';

/// Machine-readable digits of that number — a receipt only counts as a
/// valid payment when the credited account ends with these digits.
const String kPayTelebirrDigits = '989680816';

/// Name registered on that Telebirr account (also how the receipt's
/// "Credited Party name" is matched).
const String kPayTelebirrName = 'Novel Wolde Michael';

/// Pricing. A receipt unlocks the matching plan by its EXACT settled
/// amount — see `receipt_activation.dart`.
const int kMonthlyPriceEtb = 150;
const int kMonthlyPlanDays = 31;
const int kYearlyPriceEtb = 1200;
const int kYearlyPlanDays = 366;

/// How many days back a payment receipt may still be used to activate
/// (users activate right after paying; older receipts are stale).
const int kActivationReceiptMaxAgeDays = 7;

/// Free checks before the paywall appears.
const int kFreeTrialChecks = 5;
