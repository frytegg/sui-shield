#[test_only]
module gas_insurance_mvp::d_acceptance_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured};
use sui::test_scenario as ts;
use sui::clock;
use sui::coin;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;

fun post_offer_return_id(
    book: &mut mkt::Book,
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    policy_type: u8,
    strike: u64,
    premium_mist: u64,
    max_txs: u64,
    coverage: u64
): ID {
    let now = clock::timestamp_ms(clk);
    let start_ms = now;
    let expiry_ms = now + 3_600_000;
    let collateral_coin = mint_coin(coverage, scen);
    mkt::post_offer(
        book,
        policy_type,
        strike,
        premium_mist,
        start_ms,
        expiry_ms,
        max_txs,
        collateral_coin,
        coverage,
        scen.ctx()
    )
}

// D) Acceptation

#[test]
fun test_accept_offer_in_window_ok_creates_policy_and_meta() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Tx1: l’assureur poste une offre WINDOW
    let mut offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        offer_id = post_offer_return_id(
            &mut book, &mut scen, &clk,
            /*WINDOW*/ 1, /*strike*/ 1200, /*premium*/ 3 * one_sui(),
            /*max_txs*/ 3, /*coverage*/ 6 * one_sui()
        );
        ts::return_shared(book);
    };

    // Tx2: l’assuré accepte dans la fenêtre avec un coin premium exact
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(3 * one_sui(), &mut scen);
        mkt::accept_offer(&mut book, &clk, offer_id, premium_coin, scen.ctx());
        assert!(mkt::count_policies(&book) == 1, 0);
        ts::return_shared(book);
    };

    // Tx3: vérifie le Policy via getters du module core
    scen.next_tx(helpers::admin());
    {
        let pol = scen.take_shared<core::Policy>();
        assert!(core::insured_of(&pol) == insured(), 1);
        assert!(core::insurer_of(&pol) == insurer(), 2);
        assert!(core::strike_of(&pol) == 1200, 3);
        let exp = core::expiry_of(&pol);
        let now2 = clock::timestamp_ms(&clk);
        assert!(exp >= now2, 4);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_accept_offer_out_of_window_abort() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Tx1: l’assureur poste ONE_TIME
    let mut offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        offer_id = post_offer_return_id(
            &mut book, &mut scen, &clk,
            /*ONE_TIME*/ 0, /*strike*/ 1000, /*premium*/ 1 * one_sui(),
            /*max_txs*/ 1, /*coverage*/ 2 * one_sui()
        );
        ts::return_shared(book);
    };

    // Avance le temps au-delà de l’expiration
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    // Tx2: l’assuré tente d’accepter hors fenêtre => abort
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(1 * one_sui(), &mut scen);
        mkt::accept_offer(&mut book, &clk, offer_id, premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_accept_offer_premium_mismatch_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Tx1: l’assureur poste WINDOW premium = 3 SUI
    let mut offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        offer_id = post_offer_return_id(
            &mut book, &mut scen, &clk,
            /*WINDOW*/ 1, /*strike*/ 1500, /*premium*/ 3 * one_sui(),
            /*max_txs*/ 2, /*coverage*/ 5 * one_sui()
        );
        ts::return_shared(book);
    };

    // Tx2: l’assuré envoie un coin premium != 3 SUI => abort
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let wrong_premium_coin = mint_coin(2 * one_sui(), &mut scen); // 2 SUI != 3 SUI
        mkt::accept_offer(&mut book, &clk, offer_id, wrong_premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
