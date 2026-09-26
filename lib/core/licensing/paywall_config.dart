/// Paywall + activation constants. THE OWNER EDITS THIS FILE with their
/// real payment details — everything the user sees on the paywall comes
/// from here, so one edit rebrands the whole flow.
library;

/// Telebirr account that receives the 150 ETB/month payments.
const String kPayTelebirrNumber = '09XX-XXX-XXX'; // TODO(owner): your number

/// Name shown on that Telebirr account (so users know it is yours).
const String kPayTelebirrName = 'Mahtem';

/// Where users send the device code + payment receipt and receive their
/// activation code (Telegram is the usual channel).
const String kSupportTelegram = '@your_handle'; // TODO(owner): your handle

const String kSupportTelegramLink = 'https://t.me/your_handle';

/// Pricing.
const int kMonthlyPriceEtb = 150;
const int kMonthlyPlanDays = 31;
const int kYearlyPriceEtb = 1200;
const int kYearlyPlanDays = 366;

/// Free checks before the paywall appears.
const int kFreeTrialChecks = 5;
