#[test_only]
module gas_insurance_mvp::e_premium_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured};
use sui::test_scenario as ts;
use sui::clock;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_insurance as core;
use gas_insurance_mvp::gas_oracle as oracle;

/// Crée une policy WINDOW acceptée par l’assuré.
fun mk_policy_and_get_id(scen: &mut ts::Scenario, clk: &clock::Clock, premium_sui: u64): ID {
    // Tx#1: assureur poste l’offre
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let now = clock::timestamp_ms(clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;
        let strike = 1_200;
        let coverage = 6 * one_sui();
        let max_txs: u64 = 3;
        let policy_type: u8 = 1; // WINDOW
        let collateral = mint_coin(coverage, scen);
        let offer_id = mkt::post_offer(
            &mut book,
            policy_type,
            strike,
            /*premium_mist*/ premium_sui,
            start_ms,
            expiry_ms,
            max_txs,
            collateral,
            coverage,
            scen.ctx()
        );
        ts::return_shared(book);

        // Tx#2: assuré accepte avec la prime exacte
        scen.next_tx(insured());
        {
            let mut book2 = scen.take_shared<mkt::Book>();
            let premium_coin = mint_coin(premium_sui, scen);
            mkt::accept_offer(&mut book2, clk, offer_id, premium_coin, scen.ctx());
            ts::return_shared(book2);
        };
    };

    // Tx#3: lit la Policy partagée pour récupérer son ID
    scen.next_tx(helpers::admin());
    {
        let pol = scen.take_shared<core::Policy>();
        let pid = core::id_of(&pol);
        ts::return_shared(pol);
        pid
    }
}

/// E) Prime: test_withdraw_premium_ok_only_insurer
#[test]
fun test_withdraw_premium_ok_only_insurer() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let _policy_id = mk_policy_and_get_id(&mut scen, &clk, /*premium*/ 3 * one_sui());

    // Tx: l’assureur retire la prime en passant &mut Policy
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::withdraw_premium(&mut book, &mut pol, scen.ctx());
        ts::return_shared(book);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// E) Prime: test_withdraw_premium_twice_abort
#[test, expected_failure]
fun test_withdraw_premium_twice_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let _policy_id = mk_policy_and_get_id(&mut scen, &clk, /*premium*/ 2 * one_sui());

    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::withdraw_premium(&mut book, &mut pol, scen.ctx()); // OK
        mkt::withdraw_premium(&mut book, &mut pol, scen.ctx()); // abort attendu
        ts::return_shared(book);
        ts::return_shared(pol);
    };

    // Cleanup même sur expected_failure (n’exécuté que si pas d’abort)
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

/// E) Prime: test_withdraw_premium_not_insurer_abort
#[test, expected_failure]
fun test_withdraw_premium_not_insurer_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let _policy_id = mk_policy_and_get_id(&mut scen, &clk, /*premium*/ 1 * one_sui());

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();
        let mut pol = scen.take_shared<core::Policy>();
        mkt::withdraw_premium(&mut book, &mut pol, scen.ctx()); // abort attendu
        ts::return_shared(book);
        ts::return_shared(pol);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
