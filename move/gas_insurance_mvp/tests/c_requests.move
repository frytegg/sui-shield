#[test_only]
module gas_insurance_mvp::c_requests_tests;

use gas_insurance_mvp::helpers;
use gas_insurance_mvp::helpers::{setup_scenario, mint_coin, one_sui, insurer, insured};
use sui::test_scenario as ts;
use sui::clock;
use sui::coin;
use sui::object::ID;

use gas_insurance_mvp::gas_insurance_marketplace as mkt;
use gas_insurance_mvp::gas_oracle as oracle;

// Signatures utilisées par ces tests :
// post_request(&mut Book, u8, u64, u64, u64, u64, u64, u64, vector<coin::Coin<sui::sui::SUI>>, &mut TxContext) -> ID
// cancel_request(&mut Book, request_id: ID, &mut TxContext) -> ()
// count_requests(&Book) -> u64

/// Construit un vecteur de coins SUI pour dépôt.
fun make_deposit(amounts: vector<u64>, scen: &mut ts::Scenario): vector<coin::Coin<sui::sui::SUI>> {
    let mut v = vector::empty<coin::Coin<sui::sui::SUI>>();
    let mut i = 0;
    let n = vector::length(&amounts);
    while (i < n) {
        let amt = *vector::borrow(&amounts, i);
        let c = mint_coin(amt, scen);
        vector::push_back(&mut v, c);
        i = i + 1;
    };
    v
}

// ------------------------------
// C) Demandes
// ------------------------------

#[test]
fun test_post_request_no_deposit_ok() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 0;          // ONE_TIME
        let strike = 900;
        let premium = 1 * one_sui();
        let max_txs: u64 = 1;
        let coverage = 5 * one_sui();
        let deposit = vector::empty<coin::Coin<sui::sui::SUI>>();

        let _req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        assert!(mkt::count_requests(&book) == 1, 0);
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test]
fun test_post_request_with_deposit_ok_equals_premium() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 1;          // WINDOW
        let strike = 1_100;
        let premium = 3 * one_sui();
        let max_txs: u64 = 2;
        let coverage = 6 * one_sui();
        let deposit = make_deposit(vector[2 * one_sui(), 1 * one_sui()], &mut scen);

        let _req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        // Le succès de l’appel + count == 1 suffit pour valider
        assert!(mkt::count_requests(&book) == 1, 1);

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_post_request_with_deposit_mismatch_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 1;          // WINDOW
        let strike = 1_200;
        let premium = 3 * one_sui();
        let max_txs: u64 = 2;
        let coverage = 6 * one_sui();
        // Dépôt < premium => abort attendu
        let deposit = make_deposit(vector[2 * one_sui()], &mut scen);

        let _req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_post_request_time_rules_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        // WINDOW exige start_ms < expiry_ms
        let start_ms = now + 3_600_000;
        let expiry_ms = now;

        let policy_type: u8 = 1;          // WINDOW
        let strike = 1_000;
        let premium = 1 * one_sui();
        let max_txs: u64 = 2;
        let coverage = 5 * one_sui();
        let deposit = vector::empty<coin::Coin<sui::sui::SUI>>();

        let _req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test]
fun test_cancel_request_ok_returns_deposit() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 0;          // ONE_TIME
        let strike = 1_050;
        let premium = 2 * one_sui();
        let max_txs: u64 = 1;
        let coverage = 4 * one_sui();
        let deposit = make_deposit(vector[2 * one_sui()], &mut scen);

        let req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        assert!(mkt::count_requests(&book) == 1, 0);

        mkt::cancel_request(&mut book, req_id, scen.ctx());

        assert!(mkt::count_requests(&book) == 0, 1);

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_cancel_request_not_insured_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    let mut saved_id: ID;

    // Tx1: insured poste
    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 0;          // ONE_TIME
        let strike = 1_000;
        let premium = 1 * one_sui();
        let max_txs: u64 = 1;
        let coverage = 3 * one_sui();
        let deposit = vector::empty<coin::Coin<sui::sui::SUI>>();

        saved_id = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        ts::return_shared(book);
    };

    // Tx2: insurer tente d’annuler => abort
    scen.next_tx(insurer());
    {
        let mut book = scen.take_shared<mkt::Book>();
        mkt::cancel_request(&mut book, saved_id, scen.ctx());
        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}

#[test, expected_failure]
fun test_cancel_request_inactive_abort() {
    let (mut scen, clk) = setup_scenario();
    { mkt::init_book(scen.ctx()); oracle::init_oracle(scen.ctx()); };

    scen.next_tx(insured());
    {
        let mut book = scen.take_shared<mkt::Book>();

        let now = clock::timestamp_ms(&clk);
        let start_ms = now;
        let expiry_ms = now + 3_600_000;

        let policy_type: u8 = 0;          // ONE_TIME
        let strike = 1_000;
        let premium = 1 * one_sui();
        let max_txs: u64 = 1;
        let coverage = 3 * one_sui();
        let deposit = vector::empty<coin::Coin<sui::sui::SUI>>();

        let req_id: ID = mkt::post_request(
            &mut book,
            policy_type,
            strike,
            premium,
            start_ms,
            expiry_ms,
            max_txs,
            coverage,
            deposit,
            scen.ctx()
        );

        // 1re annulation OK
        mkt::cancel_request(&mut book, req_id, scen.ctx());
        // 2e annulation => abort
        mkt::cancel_request(&mut book, req_id, scen.ctx());

        ts::return_shared(book);
    };

    clock::destroy_for_testing(clk);
    let _ = ts::end(scen);
}
