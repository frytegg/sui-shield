#[test_only]
module gas_insurance_mvp::h_settlement_window_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;

/// Helper: crée une policy WINDOW et renvoie son ID.
fun mk_policy_window(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    strike: u64,
    premium_sui: u64,
    coverage_sui: u64,
    max_txs: u64
): ID {
    // Tx#1: assureur poste l’offre WINDOW
    let offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let policy_type: u8 = 1; // WINDOW
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

    // Tx#2: assuré accepte
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(premium_sui, scen);
        mkt::accept_offer(&mut book, clk, offer_id, premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    // Tx#3: lit la Policy et renvoie son ID
    scen.next_tx(admin());
    {
        let pol = scen.take_shared<core::Policy>();
        let pid = core::id_of(&pol);
        ts::return_shared(pol);
        pid
    }
}

// -----------------------------------------------------------------------------
// H) Règlement WINDOW
// -----------------------------------------------------------------------------

/// H1: plusieurs règlements avec mix positif et zero.
#[test]
fun test_settle_tx_window_multiple_positive_and_zero_mix() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_window(&mut scen, &clk, /*strike*/ 1_000, /*premium*/ 1 * one_sui(), /*coverage*/ 10 * one_sui(), /*max_txs*/ 3);

    // Observations: +300, 0, +400
    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, policy_id, b"w1", 1_300, scen.ctx());
      oracle::submit_gas_observation(&mut go, policy_id, b"w2", 900, scen.ctx());
      oracle::submit_gas_observation(&mut go, policy_id, b"w3", 1_400, scen.ctx());
      ts::return_shared(go); };

    // Règlements successifs
    let mut total_before = 0;
    let mut total_after = 0;

    // Tx A
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        total_before = core::collateral_value(&pol);
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"w1", scen.ctx());
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    // Tx B
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"w2", scen.ctx());
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    // Tx C
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"w3", scen.ctx());
        total_after = core::collateral_value(&pol);
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    // Attendu: baisse de 300 + 400 = 700
    assert!(total_before - total_after == 700, 0);

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// H2: plus de quota => abort.
#[test, expected_failure]
fun test_settle_tx_window_no_quota_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let policy_id = mk_policy_window(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui(), /*max_txs*/ 2);

    // Trois observations
    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, policy_id, b"q1", 1_100, scen.ctx());
      oracle::submit_gas_observation(&mut go, policy_id, b"q2", 1_050, scen.ctx());
      oracle::submit_gas_observation(&mut go, policy_id, b"q3", 1_200, scen.ctx());
      ts::return_shared(go); };

    // Deux règlements OK
    scen.next_tx(insured());
    { let mut book = scen.take_shared<mkt::Book>();
      let mut go = scen.take_shared<oracle::GasOracle>();
      let mut pol = scen.take_shared<core::Policy>();
      mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"q1", scen.ctx());
      ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol); };
    scen.next_tx(insured());
    { let mut book = scen.take_shared<mkt::Book>();
      let mut go = scen.take_shared<oracle::GasOracle>();
      let mut pol = scen.take_shared<core::Policy>();
      mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"q2", scen.ctx());
      ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol); };

    // Troisième => abort quota
    scen.next_tx(insured());
    { let mut book = scen.take_shared<mkt::Book>();
      let mut go = scen.take_shared<oracle::GasOracle>();
      let mut pol = scen.take_shared<core::Policy>();
      mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"q3", scen.ctx()); // abort attendu
      ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol); };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// H3: collatéral épuisé => payout plafonné au restant.
#[test]
fun test_settle_tx_window_collateral_exhausted_caps_payout() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Couverture faible pour forcer le cap
    let coverage = 2 * one_sui();
    let policy_id = mk_policy_window(&mut scen, &clk, /*strike*/ 1_000, /*premium*/ 1 * one_sui(), coverage, /*max_txs*/ 3);

    // Observation avec dépassement massif
    let digest = b"cap";
    scen.next_tx(admin());
    {
        let mut go = scen.take_shared<oracle::GasOracle>();
        // gas_used_mist = strike + 5 * one_sui()  => demande > couverture
        oracle::submit_gas_observation(&mut go, policy_id, digest, 1_000 + 5 * one_sui(), scen.ctx());
        ts::return_shared(go);
    };

    // Règlement: le collatéral tombe à 0
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        let before = core::collateral_value(&pol);
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, digest, scen.ctx());
        let after = core::collateral_value(&pol);
        assert!(before == coverage, 0);
        assert!(after == 0, 1);
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
