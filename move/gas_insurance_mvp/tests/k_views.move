#[test_only]
module gas_insurance_mvp::k_views_tests;

use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured, admin};
use sui::test_scenario as ts;
use sui::clock;
use sui::coin;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use sui::object::ID;
use std::vector;

// Helpers
fun mk_offer(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    policy_type: u8,
    strike: u64,
    premium: u64,
    coverage: u64,
    max_txs: u64
): ID {
    let id: ID;
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
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

fun mk_request(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    policy_type: u8,
    strike: u64,
    premium: u64,
    coverage: u64,
    max_txs: u64
): ID {
    let id: ID;
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let dep = vector::empty<coin::Coin<sui::sui::SUI>>();
        id = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            dep,
            scen.ctx()
        );
        ts::return_shared(book);
    };
    id
}

fun accept_offer_return_policy_id(
    scen: &mut ts::Scenario,
    clk: &clock::Clock,
    offer_id: ID,
    premium: u64
): ID {
    // accept
    scen.next_tx(insured());
    { let mut book = scen.take_shared<mkt::Book>();
      let coin = mint_coin(premium, scen);
      mkt::accept_offer(&mut book, clk, offer_id, coin, scen.ctx());
      ts::return_shared(book); };
    // read policy id
    scen.next_tx(admin());
    { let pol = scen.take_shared<core::Policy>();
      let pid = core::id_of(&pol);
      ts::return_shared(pol);
      pid }
}

// -----------------------------------------------------------------------------
// K1: count_*
// -----------------------------------------------------------------------------
#[test]
fun test_count_offers_requests_policies() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    // 1 offre non acceptée
    let _o1 = mk_offer(&mut scen, &clk, /*ONE_TIME*/ 0, 1_000, 1 * one_sui(), 3 * one_sui(), 1);
    // 1 demande
    let _r1 = mk_request(&mut scen, &clk, /*WINDOW*/ 1, 1_000, 2 * one_sui(), 5 * one_sui(), 3);
    // 1 offre acceptée -> crée 1 policy et retire l’offre du book
    let o2 = mk_offer(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 2 * one_sui(), 1);
    let _pid = accept_offer_return_policy_id(&mut scen, &clk, o2, 1 * one_sui());

    // Vérifs
    scen.next_tx(admin());
    {
        let book = scen.take_shared<mkt::Book>();
        assert!(mkt::count_offers(&book) == 1, 0);     // o1 reste
        assert!(mkt::count_requests(&book) == 1, 1);   // r1
        assert!(mkt::count_policies(&book) == 1, 2);   // 1 policy
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// -----------------------------------------------------------------------------
// K2: unit views (appel sans abort)
// -----------------------------------------------------------------------------
#[test]
fun test_view_offer_request_policy_meta() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    // Poster une offre et la consulter
    let o = mk_offer(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 3 * one_sui(), 1);
    scen.next_tx(admin());
    { let book = scen.take_shared<mkt::Book>();
      let _ov = mkt::view_offer(&book, o); // succès = pas d’abort
      ts::return_shared(book); };

    // Poster une demande et la consulter
    let r = mk_request(&mut scen, &clk, 1, 1_000, 2 * one_sui(), 5 * one_sui(), 3);
    scen.next_tx(admin());
    { let book = scen.take_shared<mkt::Book>();
      let _rv = mkt::view_request(&book, r);
      ts::return_shared(book); };

    // Accepter l’offre et consulter la policy meta
    let pid = accept_offer_return_policy_id(&mut scen, &clk, o, 1 * one_sui());
    scen.next_tx(admin());
    { let book = scen.take_shared<mkt::Book>();
      let _pm = mkt::view_policy_meta(&book, pid);
      ts::return_shared(book); };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// -----------------------------------------------------------------------------
// K3: batch views (longueurs égales aux IDs fournis)
// -----------------------------------------------------------------------------
#[test]
fun test_view_batches_offers_requests_policies() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); };

    // Deux offres actives
    let o1 = mk_offer(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 3 * one_sui(), 1);
    let o2 = mk_offer(&mut scen, &clk, 1, 1_000, 2 * one_sui(), 5 * one_sui(), 3);

    // Deux demandes
    let r1 = mk_request(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 3 * one_sui(), 1);
    let r2 = mk_request(&mut scen, &clk, 1, 1_000, 2 * one_sui(), 5 * one_sui(), 3);

    // Deux policies (en acceptant 2 nouvelles offres)
    let o3 = mk_offer(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 2 * one_sui(), 1);
    let o4 = mk_offer(&mut scen, &clk, 0, 1_000, 1 * one_sui(), 2 * one_sui(), 1);
    let p1 = accept_offer_return_policy_id(&mut scen, &clk, o3, 1 * one_sui());
    let p2 = accept_offer_return_policy_id(&mut scen, &clk, o4, 1 * one_sui());

    // Vues batch
    scen.next_tx(admin());
    {
        let book = scen.take_shared<mkt::Book>();

        let mut ids_o = vector::empty<ID>(); vector::push_back(&mut ids_o, o1); vector::push_back(&mut ids_o, o2);
        let ovs = mkt::view_offers(&book, ids_o);
        assert!(vector::length(&ovs) == 2, 0);

        let mut ids_r = vector::empty<ID>(); vector::push_back(&mut ids_r, r1); vector::push_back(&mut ids_r, r2);
        let rvs = mkt::view_requests(&book, ids_r);
        assert!(vector::length(&rvs) == 2, 1);

        let mut ids_p = vector::empty<ID>(); vector::push_back(&mut ids_p, p1); vector::push_back(&mut ids_p, p2);
        let pvs = mkt::view_policies(&book, ids_p);
        assert!(vector::length(&pvs) == 2, 2);

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
