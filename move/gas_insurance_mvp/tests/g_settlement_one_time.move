#[test_only]
module gas_insurance_mvp::g_settlement_one_time_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;

fun mk_policy_one_time(scen: &mut ts::Scenario, clk: &clock::Clock, strike: u64, premium_sui: u64, coverage_sui: u64): ID {
    let offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let policy_type: u8 = 0;
        let max_txs: u64 = 1;
        let collateral = mint_coin(coverage_sui, scen);
        offer_id = mkt::post_offer(
            &mut book,
            policy_type,
            strike,
            premium_sui,
            start_ms,
            expiry_ms,
            max_txs,
            collateral,
            coverage_sui,
            scen.ctx()
        );
        ts::return_shared(book);
    };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(premium_sui, scen);
        mkt::accept_offer(&mut book, clk, offer_id, premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    scen.next_tx(admin());
    {
        let pol = scen.take_shared<core::Policy>();
        let pid = core::id_of(&pol);
        ts::return_shared(pol);
        pid
    }
}

// G1
#[test]
fun test_settle_tx_one_time_positive_payout() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_one_time(&mut scen, &clk, 1_200, 1 * one_sui(), 5 * one_sui());

    let digest = b"tx_pos";
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, policy_id, digest, 1_500, scen.ctx());
        ts::return_shared(go);
    };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();

        let before = core::collateral_value(&pol);
        let strike = core::strike_of(&pol);

        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, digest, scen.ctx());

        let after = core::collateral_value(&pol);
        assert!(before - after == 1_500 - strike, 0);
        assert!(core::is_used(&pol), 1);

        ts::return_shared(book);
        ts::return_shared(go);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// G2
#[test]
fun test_settle_tx_one_time_zero_payout() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_one_time(&mut scen, &clk, 1_500, 1 * one_sui(), 5 * one_sui());

    let digest = b"tx_zero";
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, policy_id, digest, 1_200, scen.ctx());
        ts::return_shared(go);
    };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();

        let before = core::collateral_value(&pol);
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, digest, scen.ctx());
        let after = core::collateral_value(&pol);

        assert!(before == after, 0);
        assert!(core::is_used(&pol), 1);

        ts::return_shared(book);
        ts::return_shared(go);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// G3
#[test, expected_failure]
fun test_settle_tx_one_time_double_settle_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    let digest = b"tx_dual";
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, policy_id, digest, 1_300, scen.ctx());
        ts::return_shared(go);
    };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, digest, scen.ctx());
        ts::return_shared(book);
        ts::return_shared(go);
        ts::return_shared(pol);
    };

    scen.next_tx(insured());
    {
        let mut book2 = scen.take_shared<mkt::Book>();
        let mut go2 = scen.take_shared<oracle::GasOracle>();
        let mut pol2 = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book2, &mut go2, &clk, &mut pol2, digest, scen.ctx()); // abort attendu
        ts::return_shared(book2);
        ts::return_shared(go2);
        ts::return_shared(pol2);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// G4
#[test, expected_failure]
fun test_settle_tx_one_time_after_expiry_abort() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    let digest = b"tx_late";
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, policy_id, digest, 2_000, scen.ctx());
        ts::return_shared(go);
    };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, digest, scen.ctx()); // abort attendu
        ts::return_shared(book);
        ts::return_shared(go);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// G5
#[test, expected_failure]
fun test_settle_tx_one_time_already_used_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_one_time(&mut scen, &clk, 1_100, 1 * one_sui(), 5 * one_sui());

    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, policy_id, b"txA", 1_300, scen.ctx());
      ts::return_shared(go); };
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"txA", scen.ctx()); // premier OK
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    scen.next_tx(admin());
    { let mut go2 = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go2, policy_id, b"txB", 1_400, scen.ctx());
      ts::return_shared(go2); };
    scen.next_tx(insured());
    {
        let mut book2 = scen.take_shared<mkt::Book>();
        let mut go2b = scen.take_shared<oracle::GasOracle>();
        let mut pol2 = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book2, &mut go2b, &clk, &mut pol2, b"txB", scen.ctx()); // abort attendu
        ts::return_shared(book2); ts::return_shared(go2b); ts::return_shared(pol2);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
