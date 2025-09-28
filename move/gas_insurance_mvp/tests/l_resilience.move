#[test_only]
module gas_insurance_mvp::l_resilience_tests;

use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;

// Helper: crée une policy ONE_TIME valide et renvoie son ID.
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
// L1) public_share_object requis: le Book doit être partageable et lisible.
// -----------------------------------------------------------------------------
#[test]
fun test_public_share_object_required() {
    let (mut scen, clk) = setup_scenario();

    // Crée et partage le Book via l'entry
    { mkt::init_book(scen.ctx()); };

    // Nouvelle tx: on peut emprunter l'objet partagé => prouve le share public
    scen.next_tx(admin());
    {
        let book = scen.take_shared<mkt::Book>();
        assert!(mkt::count_offers(&book) == 0, 0);
        assert!(mkt::count_requests(&book) == 0, 1);
        assert!(mkt::count_policies(&book) == 0, 2);
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// -----------------------------------------------------------------------------
// L2) transfer_public requis pour les Coin<SUI>: withdraw, payout, reclaim
// doivent réussir sans retourner des Coin non transférés.
// -----------------------------------------------------------------------------
#[test]
fun test_transfer_public_required_for_coins() {
    let (mut scen, mut clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    // Crée une policy
    let pid = mk_policy_one_time(&mut scen, &clk, 1_000, 1 * one_sui(), 5 * one_sui());

    // L'assureur retire la prime -> doit transférer au destinataire
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::withdraw_premium(&mut book, &mut pol, scen.ctx());
        ts::return_shared(book); ts::return_shared(pol);
    };

    // Observation puis règlement -> payout transféré à l'assuré
    scen.next_tx(admin());
    { let mut go = scen.take_shared<oracle::GasOracle>();
      oracle::submit_gas_observation(&mut go, pid, b"tx", 2_000, scen.ctx());
      ts::return_shared(go); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut go = scen.take_shared<oracle::GasOracle>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::settle_tx(&mut book, &mut go, &clk, &mut pol, b"tx", scen.ctx());
        // Collatéral a baissé ou est identique si payout=0, mais aucune Coin fuitée
        ts::return_shared(book); ts::return_shared(go); ts::return_shared(pol);
    };

    // Reclaim après expiration -> tout le collatéral transféré à l'assureur
    let now = clock::timestamp_ms(&clk);
    clock::set_for_testing(&mut clk, now + 3_600_000 + 1);

    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::reclaim_collateral_after_expiry(&mut book, &clk, &mut pol, scen.ctx());
        assert!(core::collateral_value(&pol) == 0, 0);
        ts::return_shared(book); ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
