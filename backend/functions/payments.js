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
};
