#[test_only]
module gas_insurance_mvp::gas_insurance_tests {
    use gas_insurance_mvp::gas_insurance;                 // Module to test
    use sui::coin;                                        // Coin minting in tests
    use sui::clock;                                       // Test clock
    use sui::tx_context;                                  // Test context
    use sui::sui::SUI;                                    // SUI coin type
    use sui::test_scenario::{Self as ts};                 // Test scenarios

    /// Helper: creates a valid Policy with insured == insurer (simplifies authorizations)
    fun mk_policy(
        strike: u64,                                      // Strike price
        premium_val: u64,                                 // Premium MIST
        collateral_val: u64,                              // Collateral MIST
        duration_ms: u64,                                 // Duration before expiration
        clk: &clock::Clock,                               // On-chain clock (test)
        ctx: &mut tx_context::TxContext                   // TxContext (signer = insurer)
    ): gas_insurance::Policy {
        let insured = tx_context::sender(ctx);            // insured = insurer for tests
        let now = clock::timestamp_ms(clk);               // now (ms)
        let expiry = now + duration_ms;                   // absolute expiration

        let premium_coin = coin::mint_for_testing<SUI>(premium_val, ctx);       // premium
        let collateral_coin = coin::mint_for_testing<SUI>(collateral_val, ctx); // collateral

        gas_insurance::create_policy(
            insured,                                      // insured party
            strike,                                       // strike price
            expiry,                                       // expiry_ms
            premium_coin,                                 // premium coin
            collateral_coin,                              // collateral coin
            ctx
        )
    }

    /**********************************************************************
     * 1) Clock Adaptation: collateral withdrawal BEFORE expiration => abort
     *********************************************************************/
    #[test]
    #[expected_failure(abort_code = gas_insurance::E_WITHDRAW_NOT_ALLOWED)]
    fun withdraw_before_expiry_fails() {
        let mut ctx = tx_context::dummy();                // Test context
        let mut clk = clock::create_for_testing(&mut ctx);// Test clock
        clock::set_for_testing(&mut clk, 10_000);         // now = 10_000 ms

        // mk_policy(strike, premium, collateral, duration_ms, &Clock, &mut TxContext)
        let mut p = mk_policy(100, 10, 1_000, 5_000, &clk, &mut ctx);
        // Expires at 15_000 ms, calling before => should abort
        gas_insurance::withdraw_collateral(&mut p, &clk, &mut ctx);

        // not reached (expected abort)
        gas_insurance::consume_policy(p);
        clock::destroy_for_testing(clk);
    }

    /**********************************************************************
     * 1) Clock Adaptation: collateral withdrawal AFTER expiration => OK
     *********************************************************************/
    #[test]
    fun withdraw_after_expiry_ok() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 10_000);         // now = 10_000

        let mut p = mk_policy(100, 10, 1_000, 5_000, &clk, &mut ctx);
        clock::set_for_testing(&mut clk, 20_000);         // now > 15_000 (expired)

        gas_insurance::withdraw_collateral(&mut p, &clk, &mut ctx); // should pass
        assert!(gas_insurance::collateral_value(&p) == 0, 0);       // all withdrawn

        gas_insurance::consume_policy(p);                  // cleanup
        clock::destroy_for_testing(clk);
    }

    #[test]
    fun test_trigger_no_payout() {
        // 1) TX1: insurer @0x0 creates the policy
        let mut scenario = ts::begin(@0x0);                 // starts scenario, sender=@0x0
        let insured = @0x2;                                 // insured party
        let ctx1 = ts::ctx(&mut scenario);                  // &mut TxContext for TX1

        let premium = coin::mint_for_testing<SUI>(50, ctx1);// premium 50 MIST
        let collateral = coin::mint_for_testing<SUI>(200, ctx1); // collateral 200 MIST

        let expiry_ms = 50_000;                             // future expiry (ms)

        // creates valid Policy (insurer = sender of ctx1 = @0x0)
        let mut policy = gas_insurance::create_policy(
            insured,                // beneficiary
            100,                    // strike MIST/unit
            expiry_ms,              // absolute expiration
            premium,                // premium coin
            collateral,             // collateral coin
            ctx1                    // TX1 context
        );

        // 2) TX2: insured calls trigger_cover with gas <= strike
        ts::next_tx(&mut scenario, insured);                // changes sender -> @0x2
        let ctx2 = ts::ctx(&mut scenario);                  // &mut TxContext for TX2
        let mut clk = clock::create_for_testing(ctx2);      // creates test Clock
        clock::set_for_testing(&mut clk, 5_000);            // now=5_000ms < expiry

        gas_insurance::trigger_cover(&mut policy, 90, &clk, ctx2); // 90 <= 100 -> no payout

        // 3) Verifications: policy used, collateral intact
        assert!(gas_insurance::is_used(&policy), 1);        // marked as used
        assert!(gas_insurance::collateral_value(&policy) == 200, 2); // no debit

        // 4) Cleanup
        gas_insurance::consume_policy(policy);
        clock::destroy_for_testing(clk);
        ts::end(scenario);
    }

    #[test]
    fun test_trigger_with_payout() {
        // 1) TX1: creation by insurer @0x0
        let mut scenario = ts::begin(@0x0);                 // sender=@0x0
        let insured = @0x2;                                 // insured party
        let ctx1 = ts::ctx(&mut scenario);                  // &mut TxContext TX1

        let premium = coin::mint_for_testing<SUI>(20, ctx1);// premium 20
        let collateral = coin::mint_for_testing<SUI>(100, ctx1); // collateral 100

        let expiry_ms = 50_000;                             // future expiration

        // creates Policy
        let mut policy = gas_insurance::create_policy(
            insured,                // beneficiary
            50,                     // strike
            expiry_ms,              // absolute expiration
            premium,                // premium
            collateral,             // collateral
            ctx1                    // TX1 context
        );

        // 2) TX2: insured triggers with gas > strike
        ts::next_tx(&mut scenario, insured);                // sender=@0x2
        let ctx2 = ts::ctx(&mut scenario);                  // &mut TxContext TX2
        let mut clk = clock::create_for_testing(ctx2);      // test Clock
        clock::set_for_testing(&mut clk, 5_000);            // now=5_000ms < expiry

        // gas=80, strike=50 -> diff=30 ; payout = min(30, collateral=100) = 30
        gas_insurance::trigger_cover(&mut policy, 80, &clk, ctx2);

        // 3) Collateral decremented by 30 => 100-30=70
        assert!(gas_insurance::collateral_value(&policy) == 70, 1);
        assert!(gas_insurance::is_used(&policy), 2);        // marked as used

        // 4) Cleanup
        gas_insurance::consume_policy(policy);
        clock::destroy_for_testing(clk);
        ts::end(scenario);
    }

    /**********************************************************************
     * 2) Extreme case: gas_price - strike > collateral => everything drained
     *********************************************************************/
    #[test]
    fun extreme_payout_drains_collateral() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 1_000);          // now = 1_000

        // strike=100, premium=5, collateral=300, long duration
        let mut p = mk_policy(100, 5, 300, 1_000_000, &clk, &mut ctx);

        // gas_price=500 => diff=400 ; payout = min(400, 300) = 300
        gas_insurance::trigger_cover(&mut p, 500, &clk, &mut ctx);
        assert!(gas_insurance::collateral_value(&p) == 0, 0); // collateral drained
        assert!(gas_insurance::is_used(&p), 0);               // policy consumed

        gas_insurance::consume_policy(p);
        clock::destroy_for_testing(clk);
    }

    /**********************************************************************
     * 3) Multiple policies by same insurer (independence)
     *********************************************************************/
    #[test]
    fun multiple_policies_same_insurer_independent() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 42_000);          // arbitrary now

        // Two policies created by same sender (insurer)
        let mut p1 = mk_policy(100, 7, 1_000, 10_000, &clk, &mut ctx);
        let mut p2 = mk_policy(200, 9, 2_000, 20_000, &clk, &mut ctx);

        // Withdraw premiums independently
        let c1 = gas_insurance::withdraw_premium(&mut p1, &mut ctx);
        let c2 = gas_insurance::withdraw_premium(&mut p2, &mut ctx);
        assert!(coin::value(&c1) == 7, 0);
        assert!(coin::value(&c2) == 9, 0);

        // Trigger coverage on p1 only (price > strike)
        gas_insurance::trigger_cover(&mut p1, 101, &clk, &mut ctx);

        // Verify p2 is not affected
        assert!(gas_insurance::collateral_value(&p2) == 2_000, 0);
        assert!(!gas_insurance::is_used(&p2), 0);

        // Consume returned coins to avoid "unused"
        gas_insurance::consume_coin(c1);
        gas_insurance::consume_coin(c2);

        gas_insurance::consume_policy(p1);
        gas_insurance::consume_policy(p2);
        clock::destroy_for_testing(clk);
    }

    /**********************************************************************
     * 4) Double call to trigger_cover => failure on 2nd call
     *********************************************************************/
    #[test]
    #[expected_failure(abort_code = gas_insurance::E_POLICY_ALREADY_USED)]
    fun double_trigger_should_fail_on_second_call() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 5_000);

        let mut p = mk_policy(10, 1, 50, 60_000, &clk, &mut ctx);

        // 1st call: price > strike -> success, marks is_used = true
        gas_insurance::trigger_cover(&mut p, 20, &clk, &mut ctx);

        // 2nd call: should abort with E_POLICY_ALREADY_USED
        gas_insurance::trigger_cover(&mut p, 30, &clk, &mut ctx);

        // not reached
        gas_insurance::consume_policy(p);
        clock::destroy_for_testing(clk);
    }

    /**********************************************************************
     * Economic security: premium == 0 => E_ZERO_PREMIUM
     *********************************************************************/
    #[test]
    #[expected_failure(abort_code = gas_insurance::E_ZERO_PREMIUM)]
    fun zero_premium_aborts() {
        let mut ctx = tx_context::dummy();
        let insured = tx_context::sender(&mut ctx);
        let premium = coin::mint_for_testing<SUI>(0, &mut ctx);      // null premium
        let collateral = coin::mint_for_testing<SUI>(100, &mut ctx); // collateral 100
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 1_000);
        let now = clock::timestamp_ms(&clk);

        let p = gas_insurance::create_policy(
           insured, 50, now + 10_000, premium, collateral, &mut ctx
        );
        gas_insurance::consume_policy(p); // consume for non-abort path

        clock::destroy_for_testing(clk);
    }


    /**********************************************************************
     * Economic security: collateral < premium => E_COLLATERAL_LT_PREMIUM
     *********************************************************************/
    #[test]
    #[expected_failure(abort_code = gas_insurance::E_COLLATERAL_LT_PREMIUM)]
    fun collateral_lt_premium_aborts() {
        let mut ctx = tx_context::dummy();
        let insured = tx_context::sender(&mut ctx);
        let premium = coin::mint_for_testing<SUI>(50, &mut ctx);    // premium 50
        let collateral = coin::mint_for_testing<SUI>(20, &mut ctx); // collateral 20
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 1_000);
        let now = clock::timestamp_ms(&clk);

        let p = gas_insurance::create_policy(
            insured, 50, now + 10_000, premium, collateral, &mut ctx
        );
        gas_insurance::consume_policy(p); // consume for non-abort path

        clock::destroy_for_testing(clk);
    }


    /**********************************************************************
     * Immediate collateral withdrawal after trigger_cover (not expired) => OK
     *********************************************************************/
    #[test]
    fun withdraw_immediately_after_trigger_ok() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 10_000);

        // strike=100, premium=10, collateral=80, expires in 1h
        let mut p = mk_policy(100, 10, 80, 3_600_000, &clk, &mut ctx);

        // gas=150 => diff=50 => payout=min(50,80)=50
        gas_insurance::trigger_cover(&mut p, 150, &clk, &mut ctx);

        // Withdraw immediately, even though not expired (is_used=true)
        gas_insurance::withdraw_collateral(&mut p, &clk, &mut ctx);

        // Initial collateral 80, payout 50 => remains 30, then withdrawal => 0
        assert!(gas_insurance::collateral_value(&p) == 0, 0);

        gas_insurance::consume_policy(p);
        clock::destroy_for_testing(clk);
    }

    /**********************************************************************
     * Event "assertions": control of expected amount
     * via helper compute_cover_event_for_test before trigger
     *********************************************************************/
    #[test]
    fun cover_event_payload_matches_expectations() {
        let mut ctx = tx_context::dummy();
        let mut clk = clock::create_for_testing(&mut ctx);
        clock::set_for_testing(&mut clk, 2_000);

        let mut p = mk_policy(100, 5, 300, 1_000_000, &clk, &mut ctx);

        // Calculate expected payout for gas=250
        let (_, expected_payout) = gas_insurance::compute_cover_event_for_test(&p, 250);

        // Trigger coverage
        gas_insurance::trigger_cover(&mut p, 250, &clk, &mut ctx);

        // Initial collateral 300 ; after payout, should remain 300 - expected_payout
        let remaining = gas_insurance::collateral_value(&p);
        assert!(remaining + expected_payout == 300, 1);

        gas_insurance::consume_policy(p);
        clock::destroy_for_testing(clk);
    }
}
