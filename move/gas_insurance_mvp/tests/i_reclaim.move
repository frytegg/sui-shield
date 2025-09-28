#[test_only]
module gas_insurance_mvp::i_reclaim_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;

/// Crée une Policy ONE_TIME active et renvoie son ID.
fun mk_policy_one_time(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    strike: u64,
    premium_sui: u64,
    coverage_sui: u64
): ID {
    // Tx1: assureur poste l’offre ONE_TIME
    let offer_id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let policy_type: u8 = 0;     // ONE_TIME
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

    // Tx2: assuré accepte l’offre
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let premium_coin = mint_coin(premium_sui, scen);
        mkt::accept_offer(&mut book, clk, offer_id, premium_coin, scen.ctx());
        ts::return_shared(book);
    };

    // Tx3: lit la Policy et renvoie son ID
    scen.next_tx(admin());
    {
        let pol = scen.take_shared<core::Policy>();
        let pid = core::id_of(&pol);
        ts::return_shared(pol);
        pid
    }
}

// -----------------------------------------------------------------------------
// I) Récupération du collatéral après expiration
// -----------------------------------------------------------------------------

/// I1: après expiration, l’assureur récupère tout le collatéral.
#[test]
fun test_reclaim_collateral_after_expiry_returns_all() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    // Crée policy
    let coverage = 5 * one_sui();
    let _pid = mk_policy_one_time(&mut scen, &clk, /*strike*/ 1_000, /*premium*/ 1 * one_sui(), coverage);

    // Avance l’horloge au-delà de l’expiration
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    // Tx: assureur récupère
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();

        let before = core::collateral_value(&pol);
        // entry: reclaim_collateral_after_expiry(&mut Book, &clock::Clock, &mut Policy, &mut TxContext)
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx());
        let after = core::collateral_value(&pol);

        // Tout rendu
        assert!(before == coverage, 0);
        assert!(after == 0, 1);

        ts::return_shared(book);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// I2: avant expiration, reclaim doit abort.
#[test, expected_failure]
fun test_reclaim_collateral_before_expiry_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    let _pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 3 * one_sui());

    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx()); // abort attendu
        ts::return_shared(book);
        ts::return_shared(pol);
    };

    // consume Clock to satisfy drop rules
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}


/// I3: seul l’assureur peut récupérer => abort si autre adresse.
#[test, expected_failure]
fun test_reclaim_collateral_not_insurer_abort() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    let _pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 4 * one_sui());

    // Avance l’horloge après l’expiration
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    // Tx: un tiers tente => abort
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx()); // abort attendu
        ts::return_shared(book);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
