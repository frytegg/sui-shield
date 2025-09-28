#[test_only]
module gas_insurance_mvp::f_oracle_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;
use std::option;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_oracle as oracle;

/// Crée une offre ONE_TIME et renvoie son ID (clé d’observation).
fun mk_offer_id(scen: &mut ts::Scenario, clk: &clock::Clock): ID {
    let mut id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let policy_type: u8 = 0;
        let strike = 1_000;
        let premium = 1 * one_sui();
        let max_txs: u64 = 1;
        let coverage = 2 * one_sui();
        let collateral = mint_coin(coverage, scen);
        id = mkt::post_offer(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            collateral,
            coverage,
            scen.ctx()
        );
        ts::return_shared(book);
    };
    id
}

// -----------------------------------------------------------------------------
// F) Oracle
// -----------------------------------------------------------------------------

#[test]
fun test_set_operator_add_remove_ok_only_admin() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::set_operator(&mut go, insured(), /*enable*/ true, scen.ctx());
        oracle::set_operator(&mut go, insured(), /*enable*/ false, scen.ctx());
        ts::return_shared(go);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test]
fun test_submit_observation_ok_by_operator_or_admin() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let id_op = mk_offer_id(&mut scen, &clk);
    let id_admin = mk_offer_id(&mut scen, &clk);

    // Admin active insured() comme opérateur
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::set_operator(&mut go, insured(), true, scen.ctx());
        ts::return_shared(go);
    };

    // Opérateur publie
    scen.next_tx(insured());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, id_op, b"op1", /*mist*/ 1_500, scen.ctx());
        ts::return_shared(go);
    };

    // Admin publie
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, id_admin, b"ad1", /*mist*/ 2_000, scen.ctx());
        // Vérifie Some sur les deux
        let some1 = oracle::get_observed_gas(&go, id_op, b"op1");
        let some2 = oracle::get_observed_gas(&go, id_admin, b"ad1");
        assert!(option::is_some(&some1), 0);
        assert!(option::is_some(&some2), 1);
        ts::return_shared(go);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_submit_observation_unauthorized_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let id1 = mk_offer_id(&mut scen, &clk);

    // insured() n’est pas opérateur
    scen.next_tx(insured());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, id1, b"unauth", 1_234, scen.ctx()); // abort attendu
        ts::return_shared(go);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_submit_observation_duplicate_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let id1 = mk_offer_id(&mut scen, &clk);

    // Admin envoie deux fois même (policy_id, tx_digest)
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::submit_gas_observation(&mut go, id1, b"dupe", 999, scen.ctx());   // OK
        oracle::submit_gas_observation(&mut go, id1, b"dupe", 1000, scen.ctx()); // abort attendu
        ts::return_shared(go);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test]
fun test_get_observed_gas_returns_some_none() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let id_some = mk_offer_id(&mut scen, &clk);
    let id_none = mk_offer_id(&mut scen, &clk);

    // Ajoute opérateur et soumets une obs sur id_some
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        oracle::set_operator(&mut go, insured(), true, scen.ctx());
        oracle::submit_gas_observation(&mut go, id_some, b"some", 2_222, scen.ctx());
        let got_some = oracle::get_observed_gas(&go, id_some, b"some");
        let got_none = oracle::get_observed_gas(&go, id_none, b"none");
        assert!(option::is_some(&got_some), 0);
        assert!(!option::is_some(&got_none), 1);
        ts::return_shared(go);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
