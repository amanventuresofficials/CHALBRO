// Unit checks of the pure money maths in payments.js (no Firebase, no emulator).
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  computeAmounts,
  cashFeeFor,
  splitRecovery,
  autoPayoutAmount,
  UPI_PATTERN,
  MIN_PAYOUT,
  MAX_PAYOUT,
} = require("../payments");

test("cash fee is the 10% ChalBro would have kept, and never has a discount", () => {
  assert.equal(cashFeeFor(300), 30);
  assert.equal(cashFeeFor(450), 45);
  assert.equal(cashFeeFor(639), 63.9);
  assert.equal(cashFeeFor(1), 0.1);
  // and it is exactly what an online payment would have taken from the helper
  assert.equal(computeAmounts(300, 0).commission, cashFeeFor(300));
});

test("a fee owed is taken out of the next online payment", () => {
  assert.deepEqual(splitRecovery(270, 30), { recovered: 30, credit: 240 });
});

test("a fee bigger than one payment is taken over several payments until it is settled", () => {
  let owed = 100;
  const credits = [];
  for (const earned of [45, 45, 45]) {
    const { recovered, credit } = splitRecovery(earned, owed);
    owed = Math.round((owed - recovered) * 100) / 100;
    credits.push(credit);
  }
  assert.deepEqual(credits, [0, 0, 35]); // nothing paid out until the fee is cleared
  assert.equal(owed, 0);
});

test("nothing owed, or odd values, change nothing", () => {
  assert.deepEqual(splitRecovery(270, 0), { recovered: 0, credit: 270 });
  assert.deepEqual(splitRecovery(270, undefined), { recovered: 0, credit: 270 });
  assert.deepEqual(splitRecovery(270, -50), { recovered: 0, credit: 270 });
  assert.deepEqual(splitRecovery(270, "abc"), { recovered: 0, credit: 270 });
});

test("recovery never takes more than the payment and keeps paise exact", () => {
  assert.deepEqual(splitRecovery(0.1, 63.9), { recovered: 0.1, credit: 0 });
  assert.deepEqual(splitRecovery(575.1, 0.3), { recovered: 0.3, credit: 574.8 });
});

test("direct payouts wait until there is at least the minimum, and are capped", () => {
  assert.equal(autoPayoutAmount(99.99), 0);
  assert.equal(autoPayoutAmount(MIN_PAYOUT), 100);
  assert.equal(autoPayoutAmount(240.7), 240); // whole rupees, the paise stay in earnings
  assert.equal(autoPayoutAmount(500000), MAX_PAYOUT);
  assert.equal(autoPayoutAmount(NaN), 0);
  assert.equal(autoPayoutAmount(-5), 0);
});

test("UPI id pattern matches the app and the rules", () => {
  for (const ok of ["ravi.k@okhdfc", "9876543210@ybl", "a_b-c@paytm"]) assert.ok(UPI_PATTERN.test(ok), ok);
  for (const bad of ["", "no-at-sign", "a@b", "x@bank name", "@okhdfc", "a b@okhdfc"]) assert.ok(!UPI_PATTERN.test(bad), bad);
});
