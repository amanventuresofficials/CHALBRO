// Pure money maths shared by the Cloud Functions. Kept free of Firebase and
// Razorpay imports so it can be unit-tested on its own.

// ChalBro keeps this share of the agreed task price; the helper gets the rest.
const PLATFORM_FEE_PERCENT = 10;

// Highest discount an admin can configure. Keeps the amount charged above
// Razorpay's ₹1 minimum for any realistic task price.
const MAX_DISCOUNT_PERCENT = 90;

/** Turns whatever is stored in metadata/paymentConfig into a safe whole percent. */
function resolveDiscountPercent(config) {
  if (!config || config.discountEnabled !== true) return 0;
  const pct = Number(config.discountPercent);
  if (!Number.isFinite(pct) || pct <= 0) return 0;
  return Math.min(Math.round(pct), MAX_DISCOUNT_PERCENT);
}

/**
 * agreedAmount: the price the poster and helper agreed on (rupees).
 * The discount is funded by ChalBro: the poster pays less, the helper's
 * earnings are still based on the full agreed price.
 */
function computeAmounts(agreedAmount, discountPercent) {
  const discountAmount = Math.round((agreedAmount * discountPercent) / 100);
  const payable = Math.max(1, agreedAmount - discountAmount);
  const commission = agreedAmount * (PLATFORM_FEE_PERCENT / 100);
  const helperEarnings = agreedAmount - commission;
  return { discountAmount, payable, commission, helperEarnings };
}

const round2 = (n) => Math.round(n * 100) / 100;

/**
 * The platform fee a helper owes when a task of [agreedAmount] was paid in cash
 * directly (the 10% fee ChalBro would otherwise have kept). No discount applies.
 */
function cashFeeFor(agreedAmount) {
  return round2(computeAmounts(agreedAmount, 0).commission);
}

/**
 * Splits a helper's [helperEarnings] from an online payment between settling the fees
 * they still owe from cash jobs ([feeDue]) and what lands in their earnings. Fees are
 * taken payment after payment until nothing is owed.
 * Returns { recovered, credit }.
 */
function splitRecovery(helperEarnings, feeDue) {
  const owed = Number.isFinite(Number(feeDue)) && Number(feeDue) > 0 ? Number(feeDue) : 0;
  const recovered = round2(Math.min(owed, Math.max(helperEarnings, 0)));
  return { recovered, credit: round2(helperEarnings - recovered) };
}

// Same limits as the app's withdrawal rules (lib/utils/withdrawal.dart, firestore.rules).
const MIN_PAYOUT = 100;
const MAX_PAYOUT = 100000;
const UPI_PATTERN = /^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9]{2,32}$/;

/** Whole rupees to send straight to a helper's UPI id from [balance], or 0 to keep waiting. */
function autoPayoutAmount(balance) {
  const whole = Math.floor(Number(balance));
  if (!Number.isFinite(whole) || whole < MIN_PAYOUT) return 0;
  return Math.min(whole, MAX_PAYOUT);
}

/** Ratings come from the client, so never trust them: whole numbers 1..5 only. */
function clampRating(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 5;
  return Math.min(5, Math.max(1, n));
}

module.exports = {
  PLATFORM_FEE_PERCENT,
  MAX_DISCOUNT_PERCENT,
  resolveDiscountPercent,
  computeAmounts,
  clampRating,
  round2,
  cashFeeFor,
  splitRecovery,
  MIN_PAYOUT,
  MAX_PAYOUT,
  UPI_PATTERN,
  autoPayoutAmount,
};
