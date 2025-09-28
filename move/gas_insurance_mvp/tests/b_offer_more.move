#[test_only]
module gas_insurance_mvp::b_offers_more_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui};
use sui::test_scenario as ts;
use sui::clock;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_oracle as oracle;

// post_offer(&mut Book, u8, u64, u64, u64, u64, u64, Coin<SUI>, u64, &mut TxContext)

#[test, expected_failure]
fun test_post_offer_invalid_type_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let mut book = scen.take_shared<mkt::Book>();
        let policy_type: u8 = 7;
        let strike = 1_000;
        let premium_mist = 1 * one_sui();
        let max_txs: u64 = 1;
        let collateral_coin = mint_coin(2 * one_sui(), &mut scen);
        let coverage_limit = 2 * one_sui();

        mkt::post_offer(
            &mut book, policy_type, strike, premium_mist,
            start_ms, expiry_ms, max_txs, collateral_coin, coverage_limit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    // Consommer les resources si le test ne panic pas
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_post_offer_time_window_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        let now = clock::timestamp_ms(&clk);
        let start_ms = now + 3_600_000;
        let expiry_ms = now;

        let mut book = scen.take_shared<mkt::Book>();
        let policy_type: u8 = 0;
        let strike = 1_000;
        let premium_mist = 1 * one_sui();
        let max_txs: u64 = 1;
        let collateral_coin = mint_coin(2 * one_sui(), &mut scen);
        let coverage_limit = 2 * one_sui();

        mkt::post_offer(
            &mut book, policy_type, strike, premium_mist,
            start_ms, expiry_ms, max_txs, collateral_coin, coverage_limit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_post_offer_max_txs_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let mut book = scen.take_shared<mkt::Book>();
        let policy_type: u8 = 1;
        let strike = 1_200;
        let premium_mist = 1 * one_sui();
        let max_txs: u64 = 0; // invalide pour WINDOW
        let collateral_coin = mint_coin(3 * one_sui(), &mut scen);
        let coverage_limit = 3 * one_sui();

        mkt::post_offer(
            &mut book, policy_type, strike, premium_mist,
            start_ms, expiry_ms, max_txs, collateral_coin, coverage_limit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_post_offer_coverage_mismatch_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let mut book = scen.take_shared<mkt::Book>();
        let policy_type: u8 = 0;
        let strike = 900;
        let premium_mist = 1 * one_sui();
        let max_txs: u64 = 1;
        let collateral_coin = mint_coin(5 * one_sui(), &mut scen);
        let coverage_limit = 4 * one_sui(); // mismatch

        mkt::post_offer(
            &mut book, policy_type, strike, premium_mist,
            start_ms, expiry_ms, max_txs, collateral_coin, coverage_limit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
