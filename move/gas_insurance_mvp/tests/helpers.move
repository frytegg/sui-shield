#[test_only]
module gas_insurance_mvp::helpers;

use sui::test_scenario as ts;
use sui::coin;
use sui::sui::SUI;
use sui::transfer;
use sui::clock;

const ADMIN: address   = @0xa11ce;
const INSURER: address = @0x111;
const INSURED: address = @0x222;

const ONE_SUI: u64 = 1_000_000_000;

public fun setup_scenario(): (ts::Scenario, clock::Clock) {
    let mut scen = ts::begin(ADMIN);
    let clk = clock::create_for_testing(scen.ctx());
    (scen, clk)
}

public fun mint_to(addr: address, amount: u64, scen: &mut ts::Scenario) {
    let c = coin::mint_for_testing<SUI>(amount, scen.ctx());
    transfer::public_transfer(c, addr);
}

public fun mint_many_to(addr: address, amounts: vector<u64>, scen: &mut ts::Scenario) {
    let mut i = 0;
    let n = vector::length(&amounts);
    while (i < n) {
        let amt = *vector::borrow(&amounts, i);
        mint_to(addr, amt, scen);
        i = i + 1;
    };
}

public fun mint_coin(amount: u64, scen: &mut ts::Scenario): coin::Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, scen.ctx())
}

public fun admin(): address { ADMIN }
public fun insurer(): address { INSURER }
public fun insured(): address { INSURED }
public fun one_sui(): u64 { ONE_SUI }
