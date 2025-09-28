#[test_only]
module gas_insurance_mvp::a_init_and_offers_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, mint_many_to};
use sui::test_scenario as ts;
use sui::clock;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_oracle as oracle;

// A) Init
#[test]
fun test_init_book_and_oracle_ok() {
    let (mut scen, clk) = setup_scenario();
    {
        mkt::init_book(scen.ctx());
        oracle::init_oracle(scen.ctx()); // prend uniquement &mut TxContext
    };
    scen.next_tx(helpers::admin());
    {
        let book = scen.take_shared<mkt::Book>(); ts::return_shared(book);
        let go = scen.take_shared<oracle::GasOracle>(); ts::return_shared(go);
    };
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

// B) Offres
// post_offer attend 10 args au total et **pas** l'adresse de l'assureur.
// L’ordre qui matche les messages d’erreur: 
// (&mut Book, policy_type: u8, strike: u64, premium_mist: u64,
//  coverage_limit_mist: u64, expiry_ms: u64, collateral: Coin<SUI>,
//  start_ms: u64, end_ms: u64, &mut TxContext)

#[test]
fun test_post_offer_one_time_ok() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let mut book = scen.take_shared<mkt::Book>();

        let policy_type: u8 = 0;                 // ONE_TIME
        let strike = 1_000;
        let premium_mist = 2 * helpers::one_sui();
        let coverage_limit = 5 * helpers::one_sui();
        let max_txs: u64 = 1;                    // ONE_TIME => 1
        let collateral_coin = mint_coin(5 * helpers::one_sui(), &mut scen);

        mkt::post_offer(
            &mut book,
            policy_type,          // u8
            strike,               // u64
            premium_mist,         // u64
            start_ms,             // u64
            expiry_ms,            // u64
            max_txs,              // u64
            collateral_coin,      // Coin<SUI>
            coverage_limit,       // u64
            scen.ctx()
        );

        ts::return_shared(book);
    };
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test]
fun test_post_offer_window_ok() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(helpers::insurer());
    {
        mint_many_to(helpers::insurer(), vector[5 * helpers::one_sui()], &mut scen);

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let mut book = scen.take_shared<mkt::Book>();

        let policy_type: u8 = 1;                 // WINDOW
        let strike = 1_500;
        let premium_mist = 1 * helpers::one_sui();
        let coverage_limit = 5 * helpers::one_sui();
        let max_txs: u64 = 3;                    // quota
        let collateral_coin = mint_coin(5 * helpers::one_sui(), &mut scen);

        mkt::post_offer(
            &mut book,
            policy_type,
            strike,
            premium_mist,
            start_ms,
            expiry_ms,
            max_txs,
            collateral_coin,
            coverage_limit,
            scen.ctx()
        );

        ts::return_shared(book);
    };
    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}