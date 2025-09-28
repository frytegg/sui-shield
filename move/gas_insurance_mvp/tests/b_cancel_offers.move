#[test_only]
module gas_insurance_mvp::b_cancel_offers_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_oracle as oracle;

// Signatures utilisées en test :
// post_offer(&mut Book, u8, u64, u64, u64, u64, u64, Coin<SUI>, u64, &mut TxContext) -> ID
// cancel_offer(&mut Book, offer_id: ID, &mut TxContext) -> ()
// count_offers(&Book) -> u64

/// Poste UNE offre ONE_TIME et renvoie son ID (retourné par post_offer).
fun post_one_time_offer_and_get_id(
    book: &mut mkt::Book,
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    premium: u64,
    collateral: u64,
    coverage: u64
): ID {
    // Fenêtre now -> now+1h
    let now = clock::timestamp_ms(clk);
    let start_ms = now;
    let expiry_ms = now + 3_600_000;

    // Paramètres ONE_TIME
    let policy_type: u8 = 0; // ONE_TIME
    let strike = 1_000;
    let max_txs: u64 = 1;    // ONE_TIME => 1

    // Collatéral à déposer
    let collateral_coin = mint_coin(collateral, scen);

    // Appel: renvoie l'ID logique de l'offre
    mkt::post_offer(
        book,
        policy_type,
        strike,
        premium,
        start_ms,
        expiry_ms,
        max_txs,
        collateral_coin,
        coverage,
        scen.ctx()
    )
}

/// B) Offres: test_cancel_offer_ok_returns_collateral
#[test]
fun test_cancel_offer_ok_returns_collateral() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Tx: l’assureur poste puis annule
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let premium = 1 * one_sui();
        let coverage = 5 * one_sui();
        let collateral = coverage;

        let offer_id = post_one_time_offer_and_get_id(&mut book, &mut scen, &clk, premium, collateral, coverage);
        assert!(mkt::count_offers(&book) == 1, 0);

        mkt::cancel_offer(&mut book, offer_id, scen.ctx());
        assert!(mkt::count_offers(&book) == 0, 1);

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// B) Offres: test_cancel_offer_not_insurer_abort
#[test, expected_failure]
fun test_cancel_offer_not_insurer_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let mut saved_id: ID;

    // Tx1: l’assureur poste
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium = 1 * one_sui();
        let coverage = 3 * one_sui();
        let collateral = coverage;
        saved_id = post_one_time_offer_and_get_id(&mut book, &mut scen, &clk, premium, collateral, coverage);
        ts::return_shared(book);
    };

    // Tx2: un tiers tente d’annuler => abort
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        mkt::cancel_offer(&mut book, saved_id, scen.ctx()); // doit échouer
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// B) Offres: test_cancel_offer_inactive_abort
#[test, expected_failure]
fun test_cancel_offer_inactive_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Même tx: poster, annuler, puis réannuler => abort
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium = 1 * one_sui();
        let coverage = 4 * one_sui();
        let collateral = coverage;

        let offer_id = post_one_time_offer_and_get_id(&mut book, &mut scen, &clk, premium, collateral, coverage);

        mkt::cancel_offer(&mut book, offer_id, scen.ctx()); // OK
        mkt::cancel_offer(&mut book, offer_id, scen.ctx()); // abort attendu

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
