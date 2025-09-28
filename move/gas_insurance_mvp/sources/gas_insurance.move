module gas_insurance_mvp::gas_insurance {
    // Allows the marketplace to call package APIs

    use sui::coin::{Self, Coin}; // coin utilities
    use sui::event; // events
    use sui::object::{Self, UID}; // object module and UID
    use sui::tx_context::{Self, TxContext}; // tx context
    use sui::clock::{Self as clock, Clock}; // on-chain clock
    use sui::sui::SUI;
    use sui::object::ID;

    // Error codes
    const E_CALLER_NOT_INSURER: u64 = 1; // caller must be insurer
    const E_CALLER_NOT_INSURED: u64 = 2; // caller must be insured
    const E_POLICY_ALREADY_USED: u64 = 3; // policy already used
    const E_POLICY_EXPIRED: u64 = 4; // policy expired
    const E_WITHDRAW_NOT_ALLOWED: u64 = 5; // collateral withdrawal not allowed
    const E_INVARIANT_INSURER_MISMATCH: u64 = 6; // creation invariant failed
    const E_ZERO_PREMIUM: u64 = 7; // premium must be > 0
    const E_COLLATERAL_LT_PREMIUM: u64 = 9; // collateral < premium

    /// Premium already withdrawn
    const E_PREMIUM_ALREADY_WITHDRAWN: u64 = 1001;

    /// Invariant errors
    const E_INV_COVERAGE_MISMATCH: u64 = 1100; // coverage_limit_mist != collateral_value
    const E_INV_PREMIUM_BOUND: u64 = 1101; // premium_mist > premium_coin_value
    const E_INV_EXPIRY: u64 = 1102; // expiry_ms must be > 0

    // Policy object
    public struct Policy has key, store {
        id: UID, // unique object id
        insured: address, // insured
        insurer: address, // insurer
        strike_mist_per_unit: u64, // strike in MIST per unit
        premium_mist: u64, // premium in MIST
        premium_coin: Coin<sui::sui::SUI>, // premium coin held
        collateral: Coin<sui::sui::SUI>, // locked collateral
        coverage_limit_mist: u64, // limit equals initial collateral
        expiry_ms: u64, // expiration in ms
        is_used: bool, // true once consumed
    }

    // Events
    public struct PolicyCreated has copy, store, drop {
        policy_id: vector<u8>,
        insured: address,
        insurer: address,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        expiry_ts: u64, // seconds
        collateral_mist: u64,
        coverage_limit_mist: u64, // equals collateral
    }

    public struct CoverTriggered has copy, store, drop {
        policy_id: vector<u8>,
        gas_price: u64, // observed price (MIST/unit)
        payout_mist: u64, // payout in MIST
    }

    // Policy creation
    /// Create a Policy and enforce basic economics.
    public fun create_policy(
        insured: address, // beneficiary
        strike_mist_per_unit: u64, // strike
        expiry_ms: u64, // absolute expiry (ms)
        premium_coin: Coin<sui::sui::SUI>, // premium paid
        collateral_coin: Coin<sui::sui::SUI>, // collateral deposited
        ctx: &mut TxContext
    ): Policy {
        let insurer = tx_context::sender(ctx); // caller is insurer

        let premium_value = coin::value(&premium_coin);
        let collateral_value = coin::value(&collateral_coin);

        // 1) premium > 0
        assert!(premium_value > 0, E_ZERO_PREMIUM);
        // 2) collateral >= premium
        assert!(collateral_value >= premium_value, E_COLLATERAL_LT_PREMIUM);

        // Limit equals collateral at creation
        let coverage_limit_mist = collateral_value;

        let policy = Policy {
            id: object::new(ctx),
            insured,
            insurer,
            strike_mist_per_unit,
            premium_mist: premium_value,
            premium_coin,
            collateral: collateral_coin,
            coverage_limit_mist,
            expiry_ms,
            is_used: false,
        };

        event::emit(PolicyCreated {
            policy_id: object::uid_to_bytes(&policy.id),
            insured,
            insurer,
            strike_mist_per_unit,
            premium_mist: premium_value,
            expiry_ts: expiry_ms / 1000, // ms -> s
            collateral_mist: collateral_value,
            coverage_limit_mist,
        });

        policy
    }

    /// dApp entry. Create and transfer Policy to the insured.
    public entry fun create_policy_entry(
        insured: address,
        strike_mist_per_unit: u64,
        premium_coin: Coin<sui::sui::SUI>,
        collateral_coin: Coin<sui::sui::SUI>,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let now = clock::timestamp_ms(clock); // chain time in ms
        let expiry = now + duration_ms; // absolute expiry
        let insurer = tx_context::sender(ctx); // expected insurer

        let policy = create_policy(
            insured,
            strike_mist_per_unit,
            expiry,
            premium_coin,
            collateral_coin,
            ctx
        );

        assert!(policy.insurer == insurer, E_INVARIANT_INSURER_MISMATCH);
        sui::transfer::public_transfer(policy, insured);
    }

    // Read / helpers
    public fun collateral_value(policy: &Policy): u64 { coin::value(&policy.collateral) }

    fun is_expired(p: &Policy, clock: &Clock): bool {
        let now = clock::timestamp_ms(clock);
        now >= p.expiry_ms
    }

    public fun is_used(policy: &Policy): bool { policy.is_used }

    public fun get_expiry_timestamp(policy: &Policy): u64 { policy.expiry_ms / 1000 }
    public fun get_strike_price(policy: &Policy): u64 { policy.strike_mist_per_unit }
    public fun get_insured(policy: &Policy): address { policy.insured }
    public fun get_insurer(policy: &Policy): address { policy.insurer }
    public fun get_premium(policy: &Policy): u64 { policy.premium_mist }
    public fun get_coverage_limit(policy: &Policy): u64 { policy.coverage_limit_mist }

    // Premium withdrawal (insurer)
    public fun withdraw_premium(
        policy: &mut Policy,
        ctx: &mut TxContext
    ): Coin<sui::sui::SUI> {
        assert!(policy.insurer == tx_context::sender(ctx), E_CALLER_NOT_INSURER);
        let premium_value = coin::value(&policy.premium_coin);
        coin::split(&mut policy.premium_coin, premium_value, ctx)
    }

    // Coverage trigger (insured)
    public entry fun trigger_cover(
        policy: &mut Policy,
        gas_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == policy.insured, E_CALLER_NOT_INSURED);
        assert!(!policy.is_used, E_POLICY_ALREADY_USED);
        assert!(!is_expired(policy, clock), E_POLICY_EXPIRED);

        // No payout if at or below strike
        if (gas_price <= policy.strike_mist_per_unit) {
            policy.is_used = true;
            event::emit(CoverTriggered {
                policy_id: object::uid_to_bytes(&policy.id),
                gas_price,
                payout_mist: 0,
            });
            return
        };

        // Amount above strike
        let raw = gas_price - policy.strike_mist_per_unit;

        // Cap by contract (initial limit)
        let capped_by_contract =
            if (raw < policy.coverage_limit_mist) { raw } else { policy.coverage_limit_mist };

        // Cap by available collateral
        let available = coin::value(&policy.collateral);

        // Final payout = min(contract cap, available)
        let payout =
            if (capped_by_contract < available) { capped_by_contract } else { available };

        // No payment
        if (payout == 0) {
            policy.is_used = true;
            event::emit(CoverTriggered {
                policy_id: object::uid_to_bytes(&policy.id),
                gas_price,
                payout_mist: 0,
            });
            return
        };

        // Transfer payout
        let coin_out = coin::split(&mut policy.collateral, payout, ctx);
        sui::transfer::public_transfer(coin_out, policy.insured);

        policy.is_used = true;
        event::emit(CoverTriggered {
            policy_id: object::uid_to_bytes(&policy.id),
            gas_price,
            payout_mist: payout,
        });
    }

    // Remaining collateral withdrawal (insurer)
    public entry fun withdraw_collateral(
        policy: &mut Policy,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(policy.insurer == tx_context::sender(ctx), E_CALLER_NOT_INSURER);
        assert!(policy.is_used || is_expired(policy, clock), E_WITHDRAW_NOT_ALLOWED);

        let amount = coin::value(&policy.collateral);
        if (amount == 0) { return };

        let coin_out = coin::split(&mut policy.collateral, amount, ctx);
        sui::transfer::public_transfer(coin_out, policy.insurer);
    }

    /// Create a non-shared Policy and return its ID (UID -> ID).
    /// Field model:
    /// id, insured, insurer, strike_mist_per_unit, premium_mist,
    /// premium_coin, collateral, coverage_limit_mist, expiry_ms, is_used.
    public fun create_policy_value_and_id(
        insured: address,
        insurer: address,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        premium_coin: Coin<SUI>,
        collateral: Coin<SUI>,
        coverage_limit_mist: u64,
        expiry_ms: u64,
        ctx: &mut TxContext
    ): (Policy, sui::object::ID) {
        // Build the owned policy object
        let p = Policy {
            id: object::new(ctx),
            insured,
            insurer,
            strike_mist_per_unit,
            premium_mist,
            premium_coin,
            collateral,
            coverage_limit_mist,
            expiry_ms,
            is_used: false,
        };
        // Compute its copyable ID for indexing
        let pid = object::uid_to_inner(&p.id);
        (p, pid)
    }

    /// Insurer address
    public fun insurer_of(p: &Policy): address { p.insurer }

    /// Copyable ID
    public fun id_of(p: &Policy): ID { object::uid_to_inner(&p.id) }

    /// Remaining premium amount recorded
    public fun premium_amount(p: &Policy): u64 { p.premium_mist }

    /// Withdraw the full premium once. Splits exactly `premium_mist`.
    public fun withdraw_premium_full(p: &mut Policy, ctx: &mut TxContext): Coin<SUI> {
        let amt = p.premium_mist;
        assert!(amt > 0, E_PREMIUM_ALREADY_WITHDRAWN);
        let out = coin::split(&mut p.premium_coin, amt, ctx);
        p.premium_mist = 0;
        out
    }

    /// Insured address
    public fun insured_of(p: &Policy): address { p.insured }

    /// Strike (MIST/unit)
    public fun strike_of(p: &Policy): u64 { p.strike_mist_per_unit }

    /// Expiry in ms
    public fun expiry_of(p: &Policy): u64 { p.expiry_ms }

    /// Split amount from collateral. Precondition: amount <= collateral_value(p).
    public fun split_from_collateral(p: &mut Policy, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::split(&mut p.collateral, amount, ctx)
    }

    /// Mark policy as used (ONE_TIME)
    public fun mark_used(p: &mut Policy) { p.is_used = true }

    public fun take_collateral(p: &mut Policy, ctx: &mut TxContext): Coin<SUI> {
        let amt = coin::value(&p.collateral);
        if (amt == 0) {
            coin::zero<SUI>(ctx)
        } else {
            coin::split(&mut p.collateral, amt, ctx)
        }
    }

    /// Keep invariant: coverage_limit_mist == coin::value(&collateral)
    public(package) fun sync_coverage_from_collateral(p: &mut Policy) {
        let v = sui::coin::value(&p.collateral);
        p.coverage_limit_mist = v;
    }

    /// Verify policy invariants:
    /// - coverage_limit_mist == coin::value(collateral)
    /// - premium_mist <= coin::value(premium_coin) or coverage_limit_mist == 0
    /// - expiry_ms > 0
    public fun assert_policy_invariants(p: &Policy) {
        // Declared coverage equals actual collateral
        let coll_v = coin::value(&p.collateral);
        assert!(p.coverage_limit_mist == coll_v, E_INV_COVERAGE_MISMATCH);

        // At acceptance, collateral > 0 so enforce premium ≤ coverage.
        // After payouts, allow premium > coverage if coverage is 0.
        assert!(p.premium_mist <= p.coverage_limit_mist || p.coverage_limit_mist == 0, E_INV_PREMIUM_BOUND);

        // Valid expiry
        assert!(p.expiry_ms > 0, E_INV_EXPIRY);
    }

    // Test-only: expected event payload
    #[test_only]
    public fun compute_cover_event_for_test(policy: &Policy, gas_price: u64): (vector<u8>, u64) {
        let id = object::uid_to_bytes(&policy.id); // binary id
        let diff = if (gas_price <= policy.strike_mist_per_unit) { 0 } else { gas_price - policy.strike_mist_per_unit };
        let capped_by_contract = if (diff < policy.coverage_limit_mist) { diff } else { policy.coverage_limit_mist };
        let available = coin::value(&policy.collateral);
        let payout = if (capped_by_contract < available) { capped_by_contract } else { available };
        (id, payout)
    }

    // Test helpers (object consumption)
    #[test_only]
    public fun consume_policy(policy: Policy) {
        sui::transfer::freeze_object(policy);
    }

    #[test_only]
    public fun consume_coin(c: Coin<sui::sui::SUI>) {
        sui::transfer::public_freeze_object(c);
    }
}
