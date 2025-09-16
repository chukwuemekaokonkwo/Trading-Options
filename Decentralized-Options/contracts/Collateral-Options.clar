;; STX Decentralized Options Exchange Smart Contract
;; A comprehensive decentralized marketplace for STX options trading with automated settlement
;; Features include collateral management, risk controls, fee mechanisms, and emergency safeguards
;; Supports both call and put options with full on-chain execution and settlement

;; ACCESS CONTROL

(define-constant contract-administrator tx-sender)

;; ERROR CONSTANTS

(define-constant ERR-UNAUTHORIZED-ACCESS (err u1000))
(define-constant ERR-INVALID-OPTION-IDENTIFIER (err u1001))
(define-constant ERR-OPTION-EXPIRED (err u1002))
(define-constant ERR-OPTION-ALREADY-EXERCISED (err u1003))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1004))
(define-constant ERR-INVALID-EXPIRATION (err u1005))
(define-constant ERR-INVALID-STRIKE-PRICE (err u1006))
(define-constant ERR-NOT-OPTION-HOLDER (err u1007))
(define-constant ERR-INVALID-PREMIUM (err u1008))
(define-constant ERR-INVALID-CONTRACT-SIZE (err u1009))
(define-constant ERR-UNSUPPORTED-OPTION-TYPE (err u1010))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1011))
(define-constant ERR-NOT-OPTION-WRITER (err u1012))
(define-constant ERR-OPTION-NOT-FOUND (err u1013))
(define-constant ERR-CONTRACT-PAUSED (err u1014))
(define-constant ERR-INVALID-PRICE (err u1015))
(define-constant ERR-COLLATERAL-LOCKED (err u1016))

;; OPTION TYPE CONSTANTS

(define-constant call-option-variant u1)
(define-constant put-option-variant u2)

;; OPTION STATUS CONSTANTS

(define-constant option-status-active u1)
(define-constant option-status-exercised u2)
(define-constant option-status-expired u3)

;; PLATFORM LIMITS

(define-constant min-expiration-duration-blocks u144) ;; ~24 hours
(define-constant max-expiration-duration-blocks u52560) ;; ~1 year
(define-constant min-strike-price-limit u1000) ;; 0.001 STX
(define-constant max-strike-price-limit u100000000) ;; 100 STX
(define-constant min-contract-size-limit u1)
(define-constant max-contract-size-limit u1000000)

;; PLATFORM STATE

(define-data-var trading-operations-paused bool false)
(define-data-var emergency-shutdown-mode bool false)

;; CORE DATA STRUCTURES

;; Primary options registry with collateral tracking
(define-map options-ledger
  { option-identifier: uint }
  {
    option-creator: principal,
    current-option-holder: principal,
    option-strike-price: uint,
    premium-payment-amount: uint,
    contract-expiration-block: uint,
    option-contract-type: uint,
    current-contract-status: uint,
    underlying-contract-size: uint,
    contract-creation-block: uint,
    locked-collateral-amount: uint,
    is-collateral-locked: bool
  }
)

;; Writer collateral tracking
(define-map collateral-balances
  { account-holder: principal }
  { total-locked-amount: uint, available-withdrawal-balance: uint }
)

;; Option pricing feed (for automated settlement)
(define-map market-price-feeds
  { price-feed-block: uint }
  { current-stx-price: uint, price-timestamp: uint, price-reporter: principal }
)

;; Global option counter
(define-data-var next-available-option-id uint u1)

;; Platform fee settings
(define-data-var current-platform-fee-rate uint u100) ;; 1% = 100 basis points
(define-data-var platform-fee-recipient principal tx-sender)

;; VALIDATION FUNCTIONS

(define-private (validate-option-identifier (option-identifier uint))
  (and (> option-identifier u0) (< option-identifier (var-get next-available-option-id)))
)

(define-private (validate-option-type (option-contract-type uint))
  (or (is-eq option-contract-type call-option-variant) (is-eq option-contract-type put-option-variant))
)

(define-private (check-option-is-active (option-contract-data (tuple 
    (option-creator principal) (current-option-holder principal) (option-strike-price uint)
    (premium-payment-amount uint) (contract-expiration-block uint) (option-contract-type uint)
    (current-contract-status uint) (underlying-contract-size uint) (contract-creation-block uint)
    (locked-collateral-amount uint) (is-collateral-locked bool))))
  (and 
    (< block-height (get contract-expiration-block option-contract-data))
    (is-eq (get current-contract-status option-contract-data) option-status-active)
  )
)

;; Fixed collateral calculation with proper validation
(define-private (compute-required-collateral-amount (option-contract-type uint) (option-strike-price uint) (underlying-contract-size uint))
  (begin
    ;; These inputs should already be validated before this function is called
    ;; This function now assumes validated inputs
    (if (is-eq option-contract-type call-option-variant)
      ;; Call option: collateral = contract-size * strike-price (for covered calls)
      (* underlying-contract-size option-strike-price)
      ;; Put option: collateral = contract-size * strike-price (cash-secured puts)
      (* underlying-contract-size option-strike-price)
    )
  )
)

(define-private (compute-platform-fee-amount (premium-payment-amount uint))
  (/ (* premium-payment-amount (var-get current-platform-fee-rate)) u10000)
)

;; ACCESS CONTROL FUNCTIONS

(define-private (verify-contract-administrator)
  (is-eq tx-sender contract-administrator)
)

(define-private (verify-trading-operations-active)
  (not (var-get trading-operations-paused))
)

;; COLLATERAL MANAGEMENT

(define-public (deposit-trading-collateral (deposit-amount uint))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (> deposit-amount u0) ERR-INVALID-PRICE)
    
    ;; Transfer collateral to contract
    (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
    
    ;; Update collateral tracking
    (let ((existing-collateral-record (default-to { total-locked-amount: u0, available-withdrawal-balance: u0 } 
                                          (map-get? collateral-balances { account-holder: tx-sender }))))
      (map-set collateral-balances
        { account-holder: tx-sender }
        { 
          total-locked-amount: (get total-locked-amount existing-collateral-record),
          available-withdrawal-balance: (+ (get available-withdrawal-balance existing-collateral-record) deposit-amount)
        }
      )
    )
    
    (ok true)
  )
)

(define-public (withdraw-available-collateral (withdrawal-amount uint))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (> withdrawal-amount u0) ERR-INVALID-PRICE)
    
    (let ((account-collateral-data (unwrap! (map-get? collateral-balances { account-holder: tx-sender }) 
                                    ERR-INSUFFICIENT-COLLATERAL)))
      
      ;; Check available balance
      (asserts! (>= (get available-withdrawal-balance account-collateral-data) withdrawal-amount) ERR-INSUFFICIENT-COLLATERAL)
      
      ;; Transfer collateral back to user
      (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
      
      ;; Update collateral tracking
      (map-set collateral-balances
        { account-holder: tx-sender }
        { 
          total-locked-amount: (get total-locked-amount account-collateral-data),
          available-withdrawal-balance: (- (get available-withdrawal-balance account-collateral-data) withdrawal-amount)
        }
      )
      
      (ok true)
    )
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (fetch-option-contract-details (option-identifier uint))
  (begin
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    (ok (map-get? options-ledger { option-identifier: option-identifier }))
  )
)

(define-read-only (fetch-account-collateral-info (account-holder principal))
  (map-get? collateral-balances { account-holder: account-holder })
)

(define-read-only (fetch-platform-configuration)
  {
    trading-operations-paused: (var-get trading-operations-paused),
    emergency-shutdown-mode: (var-get emergency-shutdown-mode),
    current-platform-fee-rate: (var-get current-platform-fee-rate),
    next-available-option-id: (var-get next-available-option-id)
  }
)

(define-read-only (fetch-market-price-data (price-feed-block uint))
  (map-get? market-price-feeds { price-feed-block: price-feed-block })
)

;; OPTION CREATION WITH PROPER INPUT VALIDATION

(define-public (create-new-option-contract 
    (option-strike-price uint)
    (premium-payment-amount uint)
    (contract-expiration-block uint)
    (option-contract-type uint)
    (underlying-contract-size uint))
  (let ((new-option-identifier (var-get next-available-option-id)))
    
    ;; Platform state checks
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    
    ;; Input validation BEFORE any calculations
    (asserts! (and (>= option-strike-price min-strike-price-limit) (<= option-strike-price max-strike-price-limit)) ERR-INVALID-STRIKE-PRICE)
    (asserts! (> premium-payment-amount u0) ERR-INVALID-PREMIUM)
    (asserts! (and (>= underlying-contract-size min-contract-size-limit) (<= underlying-contract-size max-contract-size-limit)) ERR-INVALID-CONTRACT-SIZE)
    (asserts! (and 
               (> contract-expiration-block (+ block-height min-expiration-duration-blocks))
               (< contract-expiration-block (+ block-height max-expiration-duration-blocks))
              ) ERR-INVALID-EXPIRATION)
    (asserts! (validate-option-type option-contract-type) ERR-UNSUPPORTED-OPTION-TYPE)
    
    ;; Now calculate required collateral with validated inputs
    (let ((calculated-collateral-requirement (compute-required-collateral-amount option-contract-type option-strike-price underlying-contract-size)))
      
      (asserts! (> calculated-collateral-requirement u0) ERR-INSUFFICIENT-COLLATERAL)
      
      ;; Check collateral availability
      (let ((writer-account-collateral (unwrap! (map-get? collateral-balances { account-holder: tx-sender }) 
                                             ERR-INSUFFICIENT-COLLATERAL)))
        (asserts! (>= (get available-withdrawal-balance writer-account-collateral) calculated-collateral-requirement) ERR-INSUFFICIENT-COLLATERAL)
        
        ;; Lock collateral
        (map-set collateral-balances
          { account-holder: tx-sender }
          { 
            total-locked-amount: (+ (get total-locked-amount writer-account-collateral) calculated-collateral-requirement),
            available-withdrawal-balance: (- (get available-withdrawal-balance writer-account-collateral) calculated-collateral-requirement)
          }
        )
      )
      
      ;; Create option contract
      (map-set options-ledger
        { option-identifier: new-option-identifier }
        {
          option-creator: tx-sender,
          current-option-holder: tx-sender,
          option-strike-price: option-strike-price,
          premium-payment-amount: premium-payment-amount,
          contract-expiration-block: contract-expiration-block,
          option-contract-type: option-contract-type,
          current-contract-status: option-status-active,
          underlying-contract-size: underlying-contract-size,
          contract-creation-block: block-height,
          locked-collateral-amount: calculated-collateral-requirement,
          is-collateral-locked: true
        }
      )
      
      ;; Increment counter
      (var-set next-available-option-id (+ new-option-identifier u1))
      
      (ok new-option-identifier)
    )
  )
)

;; OPTION TRANSFER

(define-public (transfer-option-ownership (option-identifier uint) (new-option-holder principal))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    
    (let ((option-contract-data (unwrap! (map-get? options-ledger { option-identifier: option-identifier }) 
                                ERR-OPTION-NOT-FOUND)))
      
      ;; Validation
      (asserts! (check-option-is-active option-contract-data) ERR-OPTION-EXPIRED)
      (asserts! (is-eq (get current-option-holder option-contract-data) tx-sender) ERR-NOT-OPTION-HOLDER)
      
      ;; Transfer ownership
      (map-set options-ledger
        { option-identifier: option-identifier }
        (merge option-contract-data { current-option-holder: new-option-holder })
      )
      
      (ok true)
    )
  )
)

;; OPTION PURCHASE WITH FEES

(define-public (purchase-option-contract (option-identifier uint))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    
    (let ((option-contract-data (unwrap! (map-get? options-ledger { option-identifier: option-identifier }) 
                                ERR-OPTION-NOT-FOUND))
          (calculated-platform-fee (compute-platform-fee-amount (get premium-payment-amount option-contract-data))))
      
      ;; Validation
      (asserts! (check-option-is-active option-contract-data) ERR-OPTION-EXPIRED)
      (asserts! (is-eq (get option-creator option-contract-data) (get current-option-holder option-contract-data)) ERR-UNAUTHORIZED-ACCESS)
      
      ;; Premium payment to writer
      (try! (stx-transfer? (- (get premium-payment-amount option-contract-data) calculated-platform-fee) tx-sender (get option-creator option-contract-data)))
      
      ;; Platform fee payment
      (if (> calculated-platform-fee u0)
        (try! (stx-transfer? calculated-platform-fee tx-sender (var-get platform-fee-recipient)))
        true
      )
      
      ;; Transfer ownership
      (map-set options-ledger
        { option-identifier: option-identifier }
        (merge option-contract-data { current-option-holder: tx-sender })
      )
      
      (ok true)
    )
  )
)

;; OPTION EXERCISE WITH COLLATERAL RELEASE

(define-public (exercise-call-option-contract (option-identifier uint))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    
    (let ((option-contract-data (unwrap! (map-get? options-ledger { option-identifier: option-identifier }) 
                                ERR-OPTION-NOT-FOUND))
          (total-exercise-cost (* (get option-strike-price option-contract-data) (get underlying-contract-size option-contract-data))))
      
      ;; Validation
      (asserts! (check-option-is-active option-contract-data) ERR-OPTION-EXPIRED)
      (asserts! (is-eq (get option-contract-type option-contract-data) call-option-variant) ERR-UNSUPPORTED-OPTION-TYPE)
      (asserts! (is-eq (get current-option-holder option-contract-data) tx-sender) ERR-NOT-OPTION-HOLDER)
      
      ;; Exercise payment to writer
      (try! (stx-transfer? total-exercise-cost tx-sender (get option-creator option-contract-data)))
      
      ;; Release collateral back to writer
      (let ((writer-account-collateral (unwrap! (map-get? collateral-balances { account-holder: (get option-creator option-contract-data) }) 
                                             ERR-INSUFFICIENT-COLLATERAL)))
        (map-set collateral-balances
          { account-holder: (get option-creator option-contract-data) }
          { 
            total-locked-amount: (- (get total-locked-amount writer-account-collateral) (get locked-collateral-amount option-contract-data)),
            available-withdrawal-balance: (+ (get available-withdrawal-balance writer-account-collateral) (get locked-collateral-amount option-contract-data))
          }
        )
      )
      
      ;; Mark as exercised
      (map-set options-ledger
        { option-identifier: option-identifier }
        (merge option-contract-data { current-contract-status: option-status-exercised, is-collateral-locked: false })
      )
      
      (ok true)
    )
  )
)

(define-public (exercise-put-option-contract (option-identifier uint))
  (begin
    (asserts! (verify-trading-operations-active) ERR-CONTRACT-PAUSED)
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    
    (let ((option-contract-data (unwrap! (map-get? options-ledger { option-identifier: option-identifier }) 
                                ERR-OPTION-NOT-FOUND))
          (total-payout-amount (* (get option-strike-price option-contract-data) (get underlying-contract-size option-contract-data))))
      
      ;; Validation
      (asserts! (check-option-is-active option-contract-data) ERR-OPTION-EXPIRED)
      (asserts! (is-eq (get option-contract-type option-contract-data) put-option-variant) ERR-UNSUPPORTED-OPTION-TYPE)
      (asserts! (is-eq (get current-option-holder option-contract-data) tx-sender) ERR-NOT-OPTION-HOLDER)
      
      ;; Payout from locked collateral to holder
      (try! (as-contract (stx-transfer? total-payout-amount tx-sender tx-sender)))
      
      ;; Update collateral (remaining goes back to writer)
      (let ((writer-account-collateral (unwrap! (map-get? collateral-balances { account-holder: (get option-creator option-contract-data) }) 
                                             ERR-INSUFFICIENT-COLLATERAL))
            (remaining-collateral-balance (- (get locked-collateral-amount option-contract-data) total-payout-amount)))
        (map-set collateral-balances
          { account-holder: (get option-creator option-contract-data) }
          { 
            total-locked-amount: (- (get total-locked-amount writer-account-collateral) (get locked-collateral-amount option-contract-data)),
            available-withdrawal-balance: (+ (get available-withdrawal-balance writer-account-collateral) remaining-collateral-balance)
          }
        )
      )
      
      ;; Mark as exercised
      (map-set options-ledger
        { option-identifier: option-identifier }
        (merge option-contract-data { current-contract-status: option-status-exercised, is-collateral-locked: false })
      )
      
      (ok true)
    )
  )
)

;; AUTOMATED SETTLEMENT WITH COLLATERAL RELEASE

(define-public (settle-expired-option-contract (option-identifier uint))
  (begin
    (asserts! (validate-option-identifier option-identifier) ERR-INVALID-OPTION-IDENTIFIER)
    
    (let ((option-contract-data (unwrap! (map-get? options-ledger { option-identifier: option-identifier }) 
                                ERR-OPTION-NOT-FOUND)))
      
      ;; Validation
      (asserts! (>= block-height (get contract-expiration-block option-contract-data)) ERR-UNAUTHORIZED-ACCESS)
      (asserts! (is-eq (get current-contract-status option-contract-data) option-status-active) ERR-OPTION-ALREADY-EXERCISED)
      
      ;; Release collateral back to writer
      (if (get is-collateral-locked option-contract-data)
        (let ((writer-account-collateral (unwrap! (map-get? collateral-balances { account-holder: (get option-creator option-contract-data) }) 
                                               ERR-INSUFFICIENT-COLLATERAL)))
          (map-set collateral-balances
            { account-holder: (get option-creator option-contract-data) }
            { 
              total-locked-amount: (- (get total-locked-amount writer-account-collateral) (get locked-collateral-amount option-contract-data)),
              available-withdrawal-balance: (+ (get available-withdrawal-balance writer-account-collateral) (get locked-collateral-amount option-contract-data))
            }
          )
        )
        true
      )
      
      ;; Mark as expired
      (map-set options-ledger
        { option-identifier: option-identifier }
        (merge option-contract-data { current-contract-status: option-status-expired, is-collateral-locked: false })
      )
      
      (ok true)
    )
  )
)

;; PRICE FEED MANAGEMENT (For automated settlement)

(define-public (update-market-price-feed (current-stx-price uint))
  (begin
    (asserts! (> current-stx-price u0) ERR-INVALID-PRICE)
    
    (map-set market-price-feeds
      { price-feed-block: block-height }
      { current-stx-price: current-stx-price, price-timestamp: block-height, price-reporter: tx-sender }
    )
    
    (ok true)
  )
)

;; ADMIN FUNCTIONS

(define-public (pause-trading-operations)
  (begin
    (asserts! (verify-contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (var-set trading-operations-paused true)
    (ok true)
  )
)

(define-public (resume-trading-operations)
  (begin
    (asserts! (verify-contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (var-set trading-operations-paused false)
    (ok true)
  )
)

(define-public (update-platform-fee-rate (new-fee-rate uint))
  (begin
    (asserts! (verify-contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= new-fee-rate u1000) ERR-INVALID-PRICE) ;; Max 10%
    (var-set current-platform-fee-rate new-fee-rate)
    (ok true)
  )
)

(define-public (activate-emergency-shutdown)
  (begin
    (asserts! (verify-contract-administrator) ERR-UNAUTHORIZED-ACCESS)
    (var-set emergency-shutdown-mode true)
    (var-set trading-operations-paused true)
    (ok true)
  )
)

;; CONTRACT INITIALIZATION

(begin
  (print "STX Decentralized Options Exchange Successfully Deployed")
  (var-get next-available-option-id)
)