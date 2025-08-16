;; Composable DeFi Pool - Version 2
;; Event-driven architecture with functional composition

;; === SYSTEM CONFIGURATION ===
(define-constant POOL_OWNER tx-sender)
(define-constant SCALE_FACTOR u1000000)
(define-constant SECONDS_PER_YEAR u31536000)

;; === RESPONSE CODES ===
(define-constant ERR_ACCESS_DENIED (err u201))
(define-constant ERR_INVALID_PARAMS (err u202))  
(define-constant ERR_BALANCE_TOO_LOW (err u203))
(define-constant ERR_HEALTH_CHECK_FAILED (err u204))
(define-constant ERR_POOL_INACTIVE (err u205))
(define-constant ERR_LIQUIDATION_NOT_ALLOWED (err u206))
(define-constant ERR_BORROWER_NOT_FOUND (err u207))
(define-constant ERR_OPERATION_FAILED (err u208))

;; === POOL STATE MANAGEMENT ===
(define-data-var pool-cash uint u0)
(define-data-var outstanding-loans uint u0)
(define-data-var supply-rate-index uint SCALE_FACTOR)
(define-data-var borrow-rate-index uint SCALE_FACTOR)
(define-data-var last-accrual-timestamp uint u0)

;; === YIELD CURVE PARAMETERS ===
(define-data-var base-yield uint u20000)         ;; 2%
(define-data-var slope-coefficient uint u100000) ;; 10%
(define-data-var spike-rate uint u600000)        ;; 60%
(define-data-var optimal-ratio uint u800000)     ;; 80%

;; === RISK CONTROL PARAMETERS ===
(define-data-var health-ratio-min uint u750000)  ;; 75%
(define-data-var liquidator-reward uint u100000) ;; 10%
(define-data-var treasury-cut uint u100000)      ;; 10%

;; === ACCOUNT LEDGERS ===
(define-map supplier-ledger principal {
  token-balance: uint,
  rate-snapshot: uint,
  entry-timestamp: uint
})

(define-map borrower-ledger principal {
  debt-balance: uint,
  rate-snapshot: uint,
  entry-timestamp: uint
})

(define-map security-deposits principal uint)

;; === COMPOSABLE VIEW FUNCTIONS ===

(define-read-only (compute-utilization-ratio)
  (let ((available (var-get pool-cash))
        (borrowed (var-get outstanding-loans)))
    (if (is-eq available u0)
        u0
        (let ((utilization (/ (* borrowed SCALE_FACTOR) available)))
          (if (<= utilization SCALE_FACTOR)
              utilization
              SCALE_FACTOR)))))

(define-read-only (derive-borrowing-cost)
  (let ((usage (compute-utilization-ratio))
        (threshold (var-get optimal-ratio))
        (base-cost (var-get base-yield))
        (slope (var-get slope-coefficient))
        (spike (var-get spike-rate)))
    (if (<= usage threshold)
        (+ base-cost (/ (* usage slope) SCALE_FACTOR))
        (+ (+ base-cost slope)
           (/ (* (- usage threshold) spike) (- SCALE_FACTOR threshold))))))

(define-read-only (derive-supply-yield)
  (let ((borrow-cost (derive-borrowing-cost))
        (usage (compute-utilization-ratio))
        (treasury-fee (var-get treasury-cut)))
    (/ (* (* borrow-cost usage) (- SCALE_FACTOR treasury-fee))
       (* SCALE_FACTOR SCALE_FACTOR))))

(define-read-only (calculate-supplier-balance (account principal))
  (match (map-get? supplier-ledger account)
    ledger-entry 
    (let ((scaled-tokens (get token-balance ledger-entry))
          (user-rate (get rate-snapshot ledger-entry))
          (current-rate (var-get supply-rate-index)))
      (if (> user-rate u0)
          (/ (* scaled-tokens current-rate) user-rate)
          scaled-tokens))
    u0))

(define-read-only (calculate-borrower-debt (account principal))
  (match (map-get? borrower-ledger account)
    ledger-entry
    (let ((scaled-debt (get debt-balance ledger-entry))
          (user-rate (get rate-snapshot ledger-entry))
          (current-rate (var-get borrow-rate-index)))
      (if (> user-rate u0)
          (/ (* scaled-debt current-rate) user-rate)
          scaled-debt))
    u0))

(define-read-only (calculate-collateral-value (account principal))
  (default-to u0 (map-get? security-deposits account)))

(define-read-only (assess-account-health (account principal))
  (let ((collateral-value (calculate-collateral-value account))
        (debt-amount (calculate-borrower-debt account))
        (minimum-ratio (var-get health-ratio-min)))
    (if (is-eq debt-amount u0)
        true
        (>= (/ (* collateral-value minimum-ratio) SCALE_FACTOR) debt-amount))))

;; === INTERNAL STATE PROCESSORS ===

(define-private (process-interest-accrual)
  (match (get-block-info? time (- block-height u1))
    current-time
    (let ((previous-time (var-get last-accrual-timestamp)))
      (if (> current-time previous-time)
          (let ((time-elapsed (- current-time previous-time))
                (borrow-rate (derive-borrowing-cost))
                (supply-rate (derive-supply-yield))
                (borrow-increment (/ (* borrow-rate time-elapsed) SECONDS_PER_YEAR))
                (supply-increment (/ (* supply-rate time-elapsed) SECONDS_PER_YEAR)))
            (var-set borrow-rate-index (+ (var-get borrow-rate-index) borrow-increment))
            (var-set supply-rate-index (+ (var-get supply-rate-index) supply-increment))
            (var-set last-accrual-timestamp current-time)
            (ok true))
          (ok true)))
    (ok true)))

(define-private (execute-token-transfer (from principal) (to principal) (amount uint))
  (if (is-eq from tx-sender)
      (stx-transfer? amount from to)
      (as-contract (stx-transfer? amount from to))))

;; === CORE POOL OPERATIONS ===

(define-public (contribute-liquidity (contribution uint))
  (let ((validation-result 
         (and (> contribution u0)
              (is-ok (process-interest-accrual)))))
    (asserts! validation-result ERR_INVALID_PARAMS)
    
    (try! (execute-token-transfer tx-sender (as-contract tx-sender) contribution))
    
    (let ((current-rate (var-get supply-rate-index))
          (scaled-amount (/ (* contribution SCALE_FACTOR) current-rate))
          (existing-entry (default-to 
                          { token-balance: u0, 
                            rate-snapshot: current-rate, 
                            entry-timestamp: u0 }
                          (map-get? supplier-ledger tx-sender))))
      
      (map-set supplier-ledger tx-sender {
        token-balance: (+ (get token-balance existing-entry) scaled-amount),
        rate-snapshot: current-rate,
        entry-timestamp: (default-to u0 (get-block-info? time (- block-height u1)))
      })
      
      (var-set pool-cash (+ (var-get pool-cash) contribution))
      (ok contribution))))

(define-public (retrieve-liquidity (withdrawal uint))
  (let ((validation-result
         (and (> withdrawal u0)
              (is-ok (process-interest-accrual)))))
    (asserts! validation-result ERR_INVALID_PARAMS)
    
    (let ((available-balance (calculate-supplier-balance tx-sender))
          (current-rate (var-get supply-rate-index))
          (scaled-withdrawal (/ (* withdrawal SCALE_FACTOR) current-rate))
          (existing-entry (unwrap! (map-get? supplier-ledger tx-sender) ERR_BALANCE_TOO_LOW)))
      
      (asserts! (>= available-balance withdrawal) ERR_BALANCE_TOO_LOW)
      
      (map-set supplier-ledger tx-sender {
        token-balance: (- (get token-balance existing-entry) scaled-withdrawal),
        rate-snapshot: current-rate,
        entry-timestamp: (get entry-timestamp existing-entry)
      })
      
      (var-set pool-cash (- (var-get pool-cash) withdrawal))
      (try! (execute-token-transfer (as-contract tx-sender) tx-sender withdrawal))
      (ok withdrawal))))

(define-public (lock-collateral (security-amount uint))
  (begin
    (asserts! (> security-amount u0) ERR_INVALID_PARAMS)
    (try! (execute-token-transfer tx-sender (as-contract tx-sender) security-amount))
    
    (let ((current-security (calculate-collateral-value tx-sender)))
      (map-set security-deposits tx-sender (+ current-security security-amount)))
    (ok security-amount)))

(define-public (unlock-collateral (release-amount uint))
  (begin
    (asserts! (> release-amount u0) ERR_INVALID_PARAMS)
    (let ((accrual-result (process-interest-accrual))) true)
    
    (let ((current-security (calculate-collateral-value tx-sender))
          (current-debt (calculate-borrower-debt tx-sender))
          (remaining-security (- current-security release-amount))
          (health-threshold (var-get health-ratio-min)))
      
      (asserts! (>= current-security release-amount) ERR_BALANCE_TOO_LOW)
      
      (if (> current-debt u0)
          (asserts! (>= (/ (* remaining-security health-threshold) SCALE_FACTOR) current-debt)
                   ERR_HEALTH_CHECK_FAILED)
          true)
      
      (map-set security-deposits tx-sender remaining-security)
      (try! (execute-token-transfer (as-contract tx-sender) tx-sender release-amount))
      (ok release-amount))))

(define-public (request-loan (loan-amount uint))
  (begin
    (asserts! (> loan-amount u0) ERR_INVALID_PARAMS)
    (let ((accrual-result (process-interest-accrual))) true)
    
    (let ((collateral-value (calculate-collateral-value tx-sender))
          (existing-debt (calculate-borrower-debt tx-sender))
          (health-threshold (var-get health-ratio-min))
          (max-loan-capacity (/ (* collateral-value health-threshold) SCALE_FACTOR))
          (projected-debt (+ existing-debt loan-amount))
          (current-rate (var-get borrow-rate-index))
          (scaled-loan (/ (* loan-amount SCALE_FACTOR) current-rate))
          (existing-entry (default-to 
                          { debt-balance: u0, 
                            rate-snapshot: current-rate, 
                            entry-timestamp: u0 }
                          (map-get? borrower-ledger tx-sender))))
      
      (asserts! (>= max-loan-capacity projected-debt) ERR_HEALTH_CHECK_FAILED)
      (asserts! (>= (var-get pool-cash) loan-amount) ERR_BALANCE_TOO_LOW)
      
      (map-set borrower-ledger tx-sender {
        debt-balance: (+ (get debt-balance existing-entry) scaled-loan),
        rate-snapshot: current-rate,
        entry-timestamp: (default-to u0 (get-block-info? time (- block-height u1)))
      })
      
      (var-set outstanding-loans (+ (var-get outstanding-loans) loan-amount))
      (var-set pool-cash (- (var-get pool-cash) loan-amount))
      
      (try! (execute-token-transfer (as-contract tx-sender) tx-sender loan-amount))
      (ok loan-amount))))

(define-public (service-debt (payment-amount uint))
  (begin
    (asserts! (> payment-amount u0) ERR_INVALID_PARAMS)
    (let ((accrual-result (process-interest-accrual))) true)
    
    (let ((current-debt (calculate-borrower-debt tx-sender))
          (actual-payment (if (> payment-amount current-debt) current-debt payment-amount))
          (current-rate (var-get borrow-rate-index))
          (scaled-payment (/ (* actual-payment SCALE_FACTOR) current-rate))
          (existing-entry (unwrap! (map-get? borrower-ledger tx-sender) ERR_BORROWER_NOT_FOUND)))
      
      (asserts! (> current-debt u0) ERR_BORROWER_NOT_FOUND)
      (try! (execute-token-transfer tx-sender (as-contract tx-sender) actual-payment))
      
      (map-set borrower-ledger tx-sender {
        debt-balance: (- (get debt-balance existing-entry) scaled-payment),
        rate-snapshot: current-rate,
        entry-timestamp: (get entry-timestamp existing-entry)
      })
      
      (var-set outstanding-loans (- (var-get outstanding-loans) actual-payment))
      (var-set pool-cash (+ (var-get pool-cash) actual-payment))
      (ok actual-payment))))

(define-public (execute-liquidation (target-borrower principal) (debt-coverage uint))
  (begin
    (asserts! (> debt-coverage u0) ERR_INVALID_PARAMS)
    (asserts! (not (assess-account-health target-borrower)) ERR_LIQUIDATION_NOT_ALLOWED)
    (let ((accrual-result (process-interest-accrual))) true)
    
    (let ((borrower-debt (calculate-borrower-debt target-borrower))
          (borrower-collateral (calculate-collateral-value target-borrower))
          (reward-rate (var-get liquidator-reward))
          (effective-coverage (if (> debt-coverage borrower-debt) borrower-debt debt-coverage))
          (seized-collateral (+ effective-coverage 
                              (/ (* effective-coverage reward-rate) SCALE_FACTOR))))
      
      (asserts! (<= seized-collateral borrower-collateral) ERR_BALANCE_TOO_LOW)
      (try! (execute-token-transfer tx-sender (as-contract tx-sender) effective-coverage))
      
      ;; Update borrower's debt position
      (let ((current-rate (var-get borrow-rate-index))
            (scaled-coverage (/ (* effective-coverage SCALE_FACTOR) current-rate))
            (existing-debt-entry (unwrap! (map-get? borrower-ledger target-borrower) ERR_BORROWER_NOT_FOUND)))
        (map-set borrower-ledger target-borrower {
          debt-balance: (- (get debt-balance existing-debt-entry) scaled-coverage),
          rate-snapshot: current-rate,
          entry-timestamp: (get entry-timestamp existing-debt-entry)
        }))
      
      ;; Seize collateral
      (map-set security-deposits target-borrower (- borrower-collateral seized-collateral))
      (try! (execute-token-transfer (as-contract tx-sender) tx-sender seized-collateral))
      
      ;; Update pool state
      (var-set outstanding-loans (- (var-get outstanding-loans) effective-coverage))
      (var-set pool-cash (+ (var-get pool-cash) effective-coverage))
      (ok seized-collateral))))

;; === GOVERNANCE FUNCTIONS ===

(define-public (reconfigure-yield-curve (new-base uint) (new-slope uint) (new-spike uint) (new-optimal uint))
  (begin
    (asserts! (is-eq tx-sender POOL_OWNER) ERR_ACCESS_DENIED)
    (var-set base-yield new-base)
    (var-set slope-coefficient new-slope)
    (var-set spike-rate new-spike)
    (var-set optimal-ratio new-optimal)
    (ok true)))

(define-public (adjust-risk-controls (new-health-min uint) (new-reward uint) (new-treasury uint))
  (begin
    (asserts! (is-eq tx-sender POOL_OWNER) ERR_ACCESS_DENIED)
    (var-set health-ratio-min new-health-min)
    (var-set liquidator-reward new-reward)
    (var-set treasury-cut new-treasury)
    (ok true)))

(define-public (initialize-pool-state)
  (begin
    (asserts! (is-eq tx-sender POOL_OWNER) ERR_ACCESS_DENIED)
    (match (get-block-info? time (- block-height u1))
      timestamp (var-set last-accrual-timestamp timestamp)
      false)
    (ok true)))