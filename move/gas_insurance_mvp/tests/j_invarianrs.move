#[test_only]
module gas_insurance_mvp::j_invariants_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;
use sui::transfer;

/// Helper: crée une policy ONE_TIME valide et renvoie son ID.
fun mk_policy_one_time(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    strike: u64,
    premium_sui: u64,
    coverage_sui: u64
): ID {
    let offer_id: ID;

    // Post offer
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

    // Accept
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(premium_sui, scen);
        mkt::accept_offer(&mut book, clk, offer_id, premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    // Read policy id
    scen.next_tx(admin());
    {
        let pol = scen.take_shared<core::Policy>();
        let pid = core::id_of(&pol);
        ts::return_shared(pol);
        pid
    }
}

// -----------------------------------------------------------------------------
// J) Invariants
// -----------------------------------------------------------------------------

// J1) coverage mismatch => abort (détecté au règlement).
#[test, expected_failure]
fun test_invariant_policy_coverage_mismatch_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    // Crée une observation
    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, pid, b"inv", 1_200, scen.ctx());
      ts::return_shared(go); };

    // Casse l'invariant Policy: split du collatéral sans sync
    scen.next_tx(insurer());
    {
        let mut pol = scen.take_shared<core::Policy>();
        let leak = core::split_from_collateral(&mut pol, 1_000, scen.ctx()); // 1000 mist
        transfer::public_transfer(leak, insurer()); // évite fuite de ressource
        ts::return_shared(pol);
    };

    // Tentative de règlement => abort sur assert_policy_invariants
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"inv", scen.ctx()); // abort attendu
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// J2) premium bound => abort à l’acceptation (prime > couverture).
#[test, expected_failure]
fun test_invariant_policy_premium_bound_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    // Offre avec prime 3 SUI mais collatéral 2 SUI
    let offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(&clk);
        let collateral = mint_coin(2 * one_sui(), &mut scen);
        offer_id = mkt::post_offer(
            &mut book,
            /*WINDOW/ONE_TIME*/ 0,
            /*strike*/ 1_000,
            /*premium*/ 3 * one_sui(),
            /*start*/ now,
            /*expiry*/ now + 3_600_000,
            /*max_txs*/ 1,
            collateral,
            /*coverage*/ 2 * one_sui(),
            scen.ctx()
        );
        ts::return_shared(book);
    };

    // Acceptation avec coin de 3 SUI => doit abort via invariants
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(3 * one_sui(), &mut scen);
        mkt::accept_offer(&mut book, &clk, offer_id, premium_coin, scen.ctx()); // abort attendu
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// J3) meta > collatéral => abort (détecté par assert_meta_vs_policy).
// On réduit le collatéral hors index pour créer l’écart puis on tente reclaim.
#[test, expected_failure]
fun test_invariant_meta_over_collateral_abort() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    let _pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    // Réduit collatéral sans MAJ de l’index
    scen.next_tx(insurer());
    {
        let mut pol = scen.take_shared<core::Policy>();
        let leak = core::split_from_collateral(&mut pol, 2_000, scen.ctx());
        transfer::public_transfer(leak, insurer());
        ts::return_shared(pol);
    };

    // Avance l’horloge pour pouvoir tenter reclaim
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    // Reclaim => abort sur assert (meta vs policy)
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx()); // abort attendu
        ts::return_shared(book); ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// J4) invariants vérifiés aux 3 points: accept, settle, reclaim (chemin heureux).
#[test]
fun test_invariants_checked_accept_offer_settle_reclaim() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Accept
    let pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    // settle: observation puis règlement
    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, pid, b"ok", 1_200, scen.ctx());
      ts::return_shared(go); };
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        // invariants doivent tenir avant action
        core::assert_policy_invariants(&pol);
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"ok", scen.ctx());
        // et après
        core::assert_policy_invariants(&pol);
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    // reclaim après expiration
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        core::assert_policy_invariants(&pol);
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx());
        core::assert_policy_invariants(&pol);
        ts::return_shared(book); ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
