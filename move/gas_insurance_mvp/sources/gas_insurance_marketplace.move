module gas_insurance_mvp::gas_insurance_marketplace {
    use sui::object::{UID, ID}; // object IDs
    use sui::table::Table; // on-chain key-value store
    use sui::coin::Coin; // fungible coin
    use sui::sui::SUI; // SUI type
    use std::option::Option;
    use sui::tx_context::{TxContext};
    use sui::tx_context;
    use sui::object;
    use sui::table;
    use sui::transfer;
    use sui::event;
    use sui::coin;
    use std::option;
    use std::vector;
    use gas_insurance_mvp::gas_insurance;
    use gas_insurance_mvp::gas_insurance::Policy;
    use gas_insurance_mvp::gas_oracle;
    use sui::clock::{Clock};
    use sui::clock;

    // -------- Step 1: Structures, Errors, Constants --------
    /// Marketplace policy kinds.
    /// 0 = ONE_TIME (single covered tx, start can equal expiry)
    /// 1 = WINDOW   (time window, multiple txs)
    const POLICY_TYPE_ONE_TIME: u8 = 0;
    const POLICY_TYPE_WINDOW: u8 = 1;

    /// Offer-side errors
    const E_BAD_POLICY_TYPE: u64 = 1;  // policy_type not in {0,1}
    const E_TIME: u64 = 2;             // bad time window
    const E_MAX_TXS: u64 = 3;          // inconsistent max_txs
    const E_ZERO_COLLATERAL: u64 = 4;  // collateral must be > 0
    const E_COVERAGE_MISMATCH: u64 = 5; // coverage_limit_mist != collateral value
    const E_OFFER_INACTIVE: u64 = 6;   // offer not active

    /// Generic access control
    const E_NOT_AUTHORIZED: u64 = 0;

    /// Request-side errors
    const E_REQ_BAD_POLICY_TYPE: u64 = 20;
    const E_REQ_TIME: u64 = 21;
    const E_REQ_MAX_TXS: u64 = 22;
    const E_REQ_DEPOSIT_MISMATCH: u64 = 23;
    const E_REQ_INACTIVE: u64 = 24;
    const E_ZERO_COVERAGE: u64 = 25;
    const E_ZERO_PREMIUM: u64 = 26;

    /// Acceptance and premium checks
    const E_ACCEPT_TIME: u64 = 30;     // accept outside [start_ms, expiry_ms]
    const E_PREMIUM_MISMATCH: u64 = 31; // premium coin amount mismatch

    /// Policy ops
    const E_NOT_INSURER: u64 = 40;     // caller is not insurer
    const E_POLICY_EXPIRED: u64 = 60;  // now > expiry_ms
    const E_POLICY_USED: u64 = 61;     // ONE_TIME already used
    const E_NO_REMAINING_TXS: u64 = 62; // WINDOW has no quota left
    const E_NOT_EXPIRED: u64 = 70;

    // Meta vs policy invariants
    const E_META_COVERAGE_MISMATCH: u64 = 1200; // meta exceeds real collateral
    const E_META_NEGATIVE: u64 = 1201;          // negative counters forbidden

    /// Shared order book. Indexes offers, requests, and a light policy mirror.
    public struct Book has key {
        id: UID,
        offers: Table<ID, Offer>,
        requests: Table<ID, Request>,
        policies: Table<ID, PolicyMeta>,
    }

    /// Insurer offer stored in the book.
    public struct Offer has store {
        id: ID,
        insurer: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        collateral: Coin<SUI>,
        is_active: bool,
    }

    /// Insured party request. Optional feature for bilateral matching.
    public struct Request has store {
        id: ID,
        insured: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        deposit_premium: Option<Coin<SUI>>,
        is_active: bool,
    }

    /// Minimal policy index for the marketplace. Real Policy lives in gas_insurance.
    public struct PolicyMeta has store {
        id: ID,
        policy_id: ID,
        insured: address,
        insurer: address,
        expiry_ms: u64,
        policy_type: u8,
        remaining_txs: u64,
        coverage_left_mist: u64,
    }

    // -------- Step 2: Capabilities, Access, Book Init --------
    /// Admin cap for optional governance and maintenance.
    public struct BookAdminCap has key {
        id: UID,
    }

    /// Require sender(ctx) == addr.
    fun assert_sender_is(addr: address, ctx: &TxContext) {
        let s = tx_context::sender(ctx);
        assert!(s == addr, E_NOT_AUTHORIZED);
    }

    /// Keep PolicyMeta consistent with the real Policy.
    fun assert_meta_vs_policy(meta: &PolicyMeta, policy: &gas_insurance::Policy) {
        let coll_v = gas_insurance::collateral_value(policy);
        assert!(meta.coverage_left_mist <= coll_v, E_META_COVERAGE_MISMATCH);
        assert!(meta.remaining_txs >= 0, E_META_NEGATIVE);
    }

    /// Deploy the shared book and hand the admin cap to the deployer.
    public entry fun init_book(ctx: &mut TxContext) {
        let offers_tbl = table::new<ID, Offer>(ctx);
        let requests_tbl = table::new<ID, Request>(ctx);
        let policies_tbl = table::new<ID, PolicyMeta>(ctx);

        let book = Book {
            id: object::new(ctx),
            offers: offers_tbl,
            requests: requests_tbl,
            policies: policies_tbl,
        };

        transfer::share_object(book);

        let admin = BookAdminCap { id: object::new(ctx) };
        transfer::transfer(admin, tx_context::sender(ctx));
    }

    // -------- Step 3: Events --------
    public struct OfferPosted has copy, drop {
        offer_id: ID,
        insurer: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
    }

    public struct OfferCancelled has copy, drop {
        offer_id: ID,
        insurer: address,
    }

    public struct RequestPosted has copy, drop {
        request_id: ID,
        insured: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        deposit_mist: u64,
    }

    public struct RequestCancelled has copy, drop {
        request_id: ID,
        insured: address,
    }

    /// Emitted when a policy is created through the marketplace.
    public struct PolicyCreated has copy, drop {
        policy_id: ID,
        insured: address,
        insurer: address,
        policy_type: u8,
        expiry_ms: u64,
        remaining_txs: u64,
        coverage_limit_mist: u64,
        strike_mist_per_unit: u64,
        premium_mist: u64,
    }

    public struct PremiumWithdrawn has copy, drop {
        policy_id: ID,
        insurer: address,
        premium_mist: u64,
    }

    public struct PayoutExecuted has copy, drop {
        policy_id: ID,
        insured: address,
        strike_mist_per_unit: u64,
        gas_used_mist: u64,
        payout_mist: u64,
        coverage_left_mist: u64,
        remaining_txs: u64,
    }

    public struct CollateralReclaimed has copy, drop {
        policy_id: ID,
        insurer: address,
        amount_mist: u64,
    }

    public struct PolicyExpired has copy, drop {
        policy_id: ID,
        at_ms: u64,
    }

    // -------- Step 4: Offer Functions (Insurer) --------
    /// Create a fresh logical ID by minting and discarding a temp UID.
    fun fresh_id(ctx: &mut TxContext): ID {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        object::delete(uid);
        id
    }

    /// Post an offer with locked collateral. Coverage must equal collateral.
    public entry fun post_offer(
        book: &mut Book,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        collateral: Coin<SUI>,
        coverage_limit_mist: u64,
        ctx: &mut TxContext
    ): ID {
        let insurer = tx_context::sender(ctx);

        assert!(
            policy_type == POLICY_TYPE_ONE_TIME || policy_type == POLICY_TYPE_WINDOW,
            E_BAD_POLICY_TYPE
        );

        if (policy_type == POLICY_TYPE_ONE_TIME) {
            assert!(start_ms <= expiry_ms, E_TIME);
            assert!(max_txs == 1, E_MAX_TXS);
        } else {
            assert!(start_ms < expiry_ms, E_TIME);
            assert!(max_txs >= 1, E_MAX_TXS);
        };

        let collat_value = coin::value(&collateral);
        assert!(collat_value > 0, E_ZERO_COLLATERAL);
        assert!(coverage_limit_mist == collat_value, E_COVERAGE_MISMATCH);

        let offer_id = fresh_id(ctx);

        let offer = Offer {
            id: offer_id,
            insurer,
            policy_type,
            strike_mist_per_unit,
            premium_mist,
            coverage_limit_mist,
            start_ms,
            expiry_ms,
            max_txs,
            collateral,
            is_active: true,
        };

        table::add(&mut book.offers, offer_id, offer);

        event::emit(OfferPosted {
            offer_id: offer_id,
            insurer,
            policy_type,
            strike_mist_per_unit,
            premium_mist,
            coverage_limit_mist,
            start_ms,
            expiry_ms,
            max_txs,
        });

        offer_id
    }

    /// Cancel an active offer and return collateral to the insurer.
    public entry fun cancel_offer(
        book: &mut Book,
        offer_id: ID,
        ctx: &mut TxContext
    ) {
        let offer = table::remove(&mut book.offers, offer_id);

        let Offer {
            id: _,
            insurer,
            policy_type: _,
            strike_mist_per_unit: _,
            premium_mist: _,
            coverage_limit_mist: _,
            start_ms: _,
            expiry_ms: _,
            max_txs: _,
            collateral,
            is_active,
        } = offer;

        assert_sender_is(insurer, ctx);
        assert!(is_active, E_OFFER_INACTIVE);

        event::emit(OfferCancelled { offer_id, insurer });

        transfer::public_transfer(collateral, insurer);
    }

    // -------- Step 5: Request Functions (Insured) --------
    /// Post a request. Optional premium deposit must match premium_mist if present.
    public entry fun post_request(
        book: &mut Book,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        coverage_limit_mist: u64,
        deposit_premium: vector<Coin<SUI>>,
        ctx: &mut TxContext
    ): ID {
        let insured = tx_context::sender(ctx);

        assert!(
            policy_type == POLICY_TYPE_ONE_TIME || policy_type == POLICY_TYPE_WINDOW,
            E_REQ_BAD_POLICY_TYPE
        );
        if (policy_type == POLICY_TYPE_ONE_TIME) {
            assert!(start_ms <= expiry_ms, E_REQ_TIME);
            assert!(max_txs == 1, E_REQ_MAX_TXS);
        } else {
            assert!(start_ms < expiry_ms, E_REQ_TIME);
            assert!(max_txs >= 1, E_REQ_MAX_TXS);
        };
        assert!(coverage_limit_mist > 0, E_ZERO_COVERAGE);
        assert!(premium_mist > 0, E_ZERO_PREMIUM);

        // Aggregate 0..n coins into one coin if provided.
        let mut dpv = deposit_premium;
        let mut deposit_opt: option::Option<Coin<SUI>>;
        let deposit_mist: u64;

        if (vector::length(&dpv) == 0) {
            deposit_opt = option::none<Coin<SUI>>();
            deposit_mist = 0;
        } else {
            let mut acc = coin::zero<SUI>(ctx);
            while (vector::length(&dpv) > 0) {
                let c = vector::pop_back(&mut dpv);
                coin::join(&mut acc, c);
            };
            let v = coin::value(&acc);
            assert!(v == premium_mist, E_REQ_DEPOSIT_MISMATCH);
            deposit_mist = v;
            deposit_opt = option::some(acc);
        };
        vector::destroy_empty(dpv);

        let request_id = fresh_id(ctx);
        let request = Request {
            id: request_id,
            insured,
            policy_type,
            strike_mist_per_unit,
            premium_mist,
            coverage_limit_mist,
            start_ms,
            expiry_ms,
            max_txs,
            deposit_premium: deposit_opt,
            is_active: true,
        };
        table::add(&mut book.requests, request_id, request);

        event::emit(RequestPosted {
            request_id,
            insured,
            policy_type,
            strike_mist_per_unit,
            premium_mist,
            coverage_limit_mist,
            start_ms,
            expiry_ms,
            max_txs,
            deposit_mist,
        });

        request_id
    }

    /// Cancel a request and refund the deposit if any.
    public entry fun cancel_request(
        book: &mut Book,
        request_id: ID,
        ctx: &mut TxContext
    ) {
        let request = table::remove(&mut book.requests, request_id);

        let Request {
            id: _,
            insured,
            policy_type: _,
            strike_mist_per_unit: _,
            premium_mist: _,
            coverage_limit_mist: _,
            start_ms: _,
            expiry_ms: _,
            max_txs: _,
            deposit_premium,
            is_active,
        } = request;

        assert_sender_is(insured, ctx);
        assert!(is_active, E_REQ_INACTIVE);

        let mut dp = deposit_premium;
        if (option::is_some(&dp)) {
            let coin_back = option::extract(&mut dp);
            transfer::public_transfer(coin_back, insured);
            option::destroy_none(dp);
        } else {
            option::destroy_none(dp);
        };

        event::emit(RequestCancelled { request_id, insured });
    }

    // -------- Step 6: Accept Offer -> Create Policy + Share --------
    /// Accept an active offer. Check window and premium. Create and share the Policy.
    public entry fun accept_offer(
        book: &mut Book,
        clock: &Clock,
        offer_id: ID,
        premium_coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let now = clock::timestamp_ms(clock);
        let insured = tx_context::sender(ctx);

        let offer = table::remove(&mut book.offers, offer_id);

        let Offer {
            id: _,
            insurer,
            policy_type,
            strike_mist_per_unit,
            premium_mist,
            coverage_limit_mist,
            start_ms,
            expiry_ms,
            max_txs,
            collateral,
            is_active,
        } = offer;

        assert!(is_active, E_OFFER_INACTIVE);
        assert!(start_ms <= now && now <= expiry_ms, E_ACCEPT_TIME);

        let paid = coin::value(&premium_coin);
        assert!(paid == premium_mist, E_PREMIUM_MISMATCH);

        let (policy, policy_id) = gas_insurance::create_policy_value_and_id(
            insured,
            insurer,
            strike_mist_per_unit,
            premium_mist,
            premium_coin,
            collateral,
            coverage_limit_mist,
            expiry_ms,
            ctx
        );

        let remaining = if (policy_type == POLICY_TYPE_ONE_TIME) { 1 } else { max_txs };
        let meta = PolicyMeta {
            id: fresh_id(ctx),
            policy_id,
            insured,
            insurer,
            expiry_ms,
            policy_type,
            remaining_txs: remaining,
            coverage_left_mist: coverage_limit_mist,
        };
        table::add(&mut book.policies, policy_id, meta);

        event::emit(PolicyCreated {
            policy_id,
            insured,
            insurer,
            policy_type,
            expiry_ms,
            remaining_txs: remaining,
            coverage_limit_mist: coverage_limit_mist,
            strike_mist_per_unit,
            premium_mist,
        });

        gas_insurance::assert_policy_invariants(&policy);
        let meta_ref = sui::table::borrow(&book.policies, policy_id);
        assert_meta_vs_policy(meta_ref, &policy);

        transfer::public_share_object(policy);
    }

    // -------- Step 7: Premium Withdrawal by Insurer --------
    /// Withdraw the full premium from the Policy. Insurer only.
    public entry fun withdraw_premium(
        _book: &mut Book,
        policy: &mut Policy,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let insurer = gas_insurance::insurer_of(policy);
        assert!(caller == insurer, E_NOT_INSURER);

        let policy_id = gas_insurance::id_of(policy);
        let premium_mist = gas_insurance::premium_amount(policy);

        let coin_out = gas_insurance::withdraw_premium_full(policy, ctx);

        event::emit(PremiumWithdrawn {
            policy_id,
            insurer,
            premium_mist,
        });

        transfer::public_transfer(coin_out, insurer);
    }

    // -------- Step 9: Covered Transaction Settlement --------
    /// Settle one covered tx. Pulls gas from oracle. Pays up to remaining collateral.
    public entry fun settle_tx(
        book: &mut Book,
        oracle: &mut gas_oracle::GasOracle,
        clock: &Clock,
        policy: &mut Policy,
        tx_digest: vector<u8>,
        ctx: &mut TxContext
    ) {
        let now = clock::timestamp_ms(clock);

        let pid = gas_insurance::id_of(policy);
        let insured = gas_insurance::insured_of(policy);

        let expiry = gas_insurance::expiry_of(policy);
        assert!(now <= expiry, E_POLICY_EXPIRED);

        let meta = table::borrow_mut(&mut book.policies, pid);

        gas_insurance::assert_policy_invariants(policy);
        assert_meta_vs_policy(meta, policy);

        if (meta.policy_type == POLICY_TYPE_ONE_TIME) {
            assert!(!gas_insurance::is_used(policy), E_POLICY_USED);
        } else {
            assert!(meta.remaining_txs > 0, E_NO_REMAINING_TXS);
        };

        let gas_used_mist = gas_oracle::take_observation(oracle, pid, tx_digest, ctx);

        let strike = gas_insurance::strike_of(policy);
        let payout_base = if (gas_used_mist > strike) { gas_used_mist - strike } else { 0 };

        let collat_left = gas_insurance::collateral_value(policy);
        let payout = if (payout_base < collat_left) { payout_base } else { collat_left };

        if (payout > 0) {
            assert!(meta.coverage_left_mist >= payout, E_ZERO_COLLATERAL);
            let coin_out = gas_insurance::split_from_collateral(policy, payout, ctx);
            transfer::public_transfer(coin_out, insured);
            meta.coverage_left_mist = meta.coverage_left_mist - payout;
        };

        gas_insurance::sync_coverage_from_collateral(policy);

        if (meta.policy_type == POLICY_TYPE_ONE_TIME) {
            gas_insurance::mark_used(policy);
            meta.remaining_txs = 0;
        } else {
            meta.remaining_txs = meta.remaining_txs - 1;
        };

        gas_insurance::assert_policy_invariants(policy);
        assert_meta_vs_policy(meta, policy);

        event::emit(PayoutExecuted {
            policy_id: pid,
            insured,
            strike_mist_per_unit: strike,
            gas_used_mist,
            payout_mist: payout,
            coverage_left_mist: meta.coverage_left_mist,
            remaining_txs: meta.remaining_txs,
        });
    }

    // -------- Step 10: Collateral Recovery After Expiration --------
    /// After expiry, insurer can reclaim remaining collateral. Resets meta.
    public entry fun reclaim_collateral_after_expiry(
        book: &mut Book,
        clock: &Clock,
        policy: &mut Policy,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        let insurer = gas_insurance::insurer_of(policy);
        assert!(caller == insurer, E_NOT_INSURER);

        let now = clock::timestamp_ms(clock);
        let expiry = gas_insurance::expiry_of(policy);
        assert!(now > expiry, E_NOT_EXPIRED);

        let pid = gas_insurance::id_of(policy);

        let meta = table::borrow_mut(&mut book.policies, pid);
        gas_insurance::assert_policy_invariants(policy);
        assert_meta_vs_policy(meta, policy);

        let amount = gas_insurance::collateral_value(policy);
        if (amount > 0) {
            let coin_back = gas_insurance::take_collateral(policy, ctx);
            transfer::public_transfer(coin_back, insurer);
            meta.coverage_left_mist = 0;
        };
        meta.remaining_txs = 0;

        gas_insurance::sync_coverage_from_collateral(policy);

        gas_insurance::assert_policy_invariants(policy);
        assert_meta_vs_policy(meta, policy);

        event::emit(CollateralReclaimed { policy_id: pid, insurer, amount_mist: amount });
        event::emit(PolicyExpired { policy_id: pid, at_ms: now });
    }

    /// Step 11: Read-only views for UI or indexers.
    public struct OfferView has copy, drop {
        offer_id: ID,
        insurer: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        is_active: bool,
    }

    public struct RequestView has copy, drop {
        request_id: ID,
        insured: address,
        policy_type: u8,
        strike_mist_per_unit: u64,
        premium_mist: u64,
        coverage_limit_mist: u64,
        start_ms: u64,
        expiry_ms: u64,
        max_txs: u64,
        has_deposit: bool,
        is_active: bool,
    }

    public struct PolicyMetaView has copy, drop {
        policy_id: ID,
        insured: address,
        insurer: address,
        expiry_ms: u64,
        policy_type: u8,
        remaining_txs: u64,
        coverage_left_mist: u64,
    }

    // -------- Counters --------
    public fun count_offers(book: &Book): u64 {
        sui::table::length(&book.offers)
    }

    public fun count_requests(book: &Book): u64 {
        sui::table::length(&book.requests)
    }

    public fun count_policies(book: &Book): u64 {
        sui::table::length(&book.policies)
    }

    // -------- Unit Views --------
    public fun view_offer(book: &Book, offer_id: ID): OfferView {
        let o = sui::table::borrow(&book.offers, offer_id);
        OfferView {
            offer_id,
            insurer: o.insurer,
            policy_type: o.policy_type,
            strike_mist_per_unit: o.strike_mist_per_unit,
            premium_mist: o.premium_mist,
            coverage_limit_mist: o.coverage_limit_mist,
            start_ms: o.start_ms,
            expiry_ms: o.expiry_ms,
            max_txs: o.max_txs,
            is_active: o.is_active,
        }
    }

    public fun view_request(book: &Book, request_id: ID): RequestView {
        let r = sui::table::borrow(&book.requests, request_id);
        let has_dep = std::option::is_some(&r.deposit_premium);
        RequestView {
            request_id,
            insured: r.insured,
            policy_type: r.policy_type,
            strike_mist_per_unit: r.strike_mist_per_unit,
            premium_mist: r.premium_mist,
            coverage_limit_mist: r.coverage_limit_mist,
            start_ms: r.start_ms,
            expiry_ms: r.expiry_ms,
            max_txs: r.max_txs,
            has_deposit: has_dep,
            is_active: r.is_active,
        }
    }

    public fun view_policy_meta(book: &Book, policy_id: ID): PolicyMetaView {
        let m = sui::table::borrow(&book.policies, policy_id);
        PolicyMetaView {
            policy_id: m.policy_id,
            insured: m.insured,
            insurer: m.insurer,
            expiry_ms: m.expiry_ms,
            policy_type: m.policy_type,
            remaining_txs: m.remaining_txs,
            coverage_left_mist: m.coverage_left_mist,
        }
    }

    // -------- Batch Views --------
    /// Table has no key iteration. Pass ids from your indexer.
    public fun view_offers(book: &Book, ids: vector<ID>): vector<OfferView> {
        let mut out = vector::empty<OfferView>();
        let mut i = 0;
        let n = vector::length(&ids);
        while (i < n) {
            let id = *vector::borrow(&ids, i);
            vector::push_back(&mut out, view_offer(book, id));
            i = i + 1;
        };
        out
    }

    public fun view_requests(book: &Book, ids: vector<ID>): vector<RequestView> {
        let mut out = vector::empty<RequestView>();
        let mut i = 0;
        let n = vector::length(&ids);
        while (i < n) {
            let id = *vector::borrow(&ids, i);
            vector::push_back(&mut out, view_request(book, id));
            i = i + 1;
        };
        out
    }

    public fun view_policies(book: &Book, policy_ids: vector<ID>): vector<PolicyMetaView> {
        let mut out = vector::empty<PolicyMetaView>();
        let mut i = 0;
        let n = vector::length(&policy_ids);
        while (i < n) {
            let id = *vector::borrow(&policy_ids, i);
            vector::push_back(&mut out, view_policy_meta(book, id));
            i = i + 1;
        };
        out
    }
}
