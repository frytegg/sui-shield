module gas_insurance_mvp::gas_oracle {
    use sui::object::{UID, ID};
    use sui::table;
    use sui::table::Table;
    use sui::tx_context::{TxContext};
    use sui::tx_context;
    use sui::event;
    use std::option;
    use std::option::Option;

    // Observation key: (policy_id, tx_digest)
    // Copyable, droppable, storable so it can be used as a Table key.
    public struct ObsKey has copy, drop, store {
        policy_id: ID,
        tx_digest: vector<u8>,
    }

    // Shared gas oracle
    // Needs `store` to be shareable.
    public struct GasOracle has key, store {
        id: UID,
        admin: address,
        operators: Table<address, bool>,   // allowed operators => true
        observations: Table<ObsKey, u64>,  // (policy, tx) -> gas_used_mist
    }

    // Events
    public struct GasObserved has copy, drop {
        policy_id: ID,
        observer: address,
        gas_used_mist: u64,
    }

    // Errors
    const E_NOT_ADMIN: u64        = 1;
    const E_NOT_OPERATOR: u64     = 2;
    const E_ALREADY_OBSERVED: u64 = 3;

    // Admin check
    fun assert_admin(oracle: &GasOracle, caller: address) {
        assert!(caller == oracle.admin, E_NOT_ADMIN);
    }

    // True if admin or listed operator.
    // Note: `table::contains` takes the key by value.
    fun is_operator(oracle: &GasOracle, caller: address): bool {
        if (caller == oracle.admin) { true }
        else { table::contains(&oracle.operators, caller) }
    }

    // Init: create and share the oracle; admin = sender()
    public entry fun init_oracle(ctx: &mut TxContext) {
        let ops = table::new<address, bool>(ctx);
        let obs = table::new<ObsKey, u64>(ctx);

        let oracle = GasOracle {
            id: sui::object::new(ctx),
            admin: tx_context::sender(ctx),
            operators: ops,
            observations: obs,
        };

        sui::transfer::public_share_object(oracle);
    }

    // Admin: add or remove an operator
    public entry fun set_operator(
        oracle: &mut GasOracle,
        operator: address,
        enabled: bool,
        ctx: &mut TxContext
    ) {
        assert_admin(oracle, tx_context::sender(ctx));

        if (enabled) {
            if (!table::contains(&oracle.operators, operator)) {
                table::add(&mut oracle.operators, operator, true);
            };
        } else {
            if (table::contains(&oracle.operators, operator)) {
                let _ = table::remove(&mut oracle.operators, operator);
            };
        };
    }

    // Submit an observation: (policy_id, tx_digest) -> gas_used_mist
    // Auth: admin or operator.
    public entry fun submit_gas_observation(
        oracle: &mut GasOracle,
        policy_id: ID,
        tx_digest: vector<u8>,
        gas_used_mist: u64,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        assert!(is_operator(oracle, caller), E_NOT_OPERATOR);

        let key = ObsKey { policy_id, tx_digest };

        // Avoid duplicates.
        assert!(!table::contains(&oracle.observations, key), E_ALREADY_OBSERVED);

        table::add(&mut oracle.observations, key, gas_used_mist);

        event::emit(GasObserved { policy_id, observer: caller, gas_used_mist });
    }

    // Read: return Option<u64> if present
    public fun get_observed_gas(
        oracle: &GasOracle,
        policy_id: ID,
        tx_digest: vector<u8>
    ): Option<u64> {
        let key = ObsKey { policy_id, tx_digest };

        if (table::contains(&oracle.observations, key)) {
            let v_ref = table::borrow(&oracle.observations, key);
            let v = *v_ref;
            option::some(v)
        } else {
            option::none()
        }
    }

    // Take and delete an observation; aborts if missing
    public entry fun take_observation(
        oracle: &mut GasOracle,
        policy_id: ID,
        tx_digest: vector<u8>,
        _ctx: &mut TxContext
    ): u64 {
        let key = ObsKey { policy_id, tx_digest };
        let gas_used = table::remove(&mut oracle.observations, key);
        gas_used
    }
}
