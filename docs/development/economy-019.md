# Early economy rates

The approved 0.1.9 rates are 200 coins per completed payment, 280 coins for a new Basic oak table set, and wages of 18/11/10/11 coins per game minute for chef/waiter/cleaner/cashier. One of each role costs 50 coins per game minute. The level-2 stove upgrade remains 180. Other catalog and hiring prices are unchanged.

These rates affect future transactions and newly worked simulation time. Loading a save does not credit or debit the wallet, recompute historical meal income, clear wage debt, or revalue an already accrued payroll fraction. A partially accrued old-rate minute finishes by adding only the remaining newly worked time at the new rate. The existing accrued amount and fractional carry stay exact.

Dining sets already have an authoritative `paid_cost` ledger. New Basic oak sets record 280 and refund 140; historical 140-coin sets retain their 70-coin refund. A legacy oak set without that field still inherits 140. Both historical purchase amounts remain valid. Moving, rebuilding, saving or loading a set preserves its basis; selling either member removes the whole set and refunds once. Legacy individual table/chair prices remain 100/40, and an automatically linked legacy pair retains its 140 basis. No new save schema or retroactive conversion is needed.

The focused `test_economy_revision` suite covers exact charges, both-member/group refunds, mixed old/new sets, movement and save roundtrips, legacy loose components, invalid and atomic failures, old payroll/debt carry, and actual register plus legacy settlement. Run it through `tests/run_integration_candidate.py --only test_economy_revision --output <new-output-directory>` with an isolated generated profile.
