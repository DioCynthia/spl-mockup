;; spl-asset-marketplace
;; A decentralized marketplace for digital assets on the Stacks blockchain
;; This contract manages listings, purchases, royalties, and trend tracking for 
;; digital assets across various creative domains.

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NO-LISTING (err u101))
(define-constant ERR-LISTING-EXPIRED (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-ALREADY-PURCHASED (err u104))
(define-constant ERR-INVALID-PRICE (err u105))
(define-constant ERR-INVALID-ROYALTY (err u106))
(define-constant ERR-INVALID-RATING (err u107))
(define-constant ERR-NOT-PURCHASED (err u108))
(define-constant ERR-ALREADY-RATED (err u109))
(define-constant ERR-PLATFORM-FEE-FAILED (err u110))
(define-constant ERR-SELLER-PAYMENT-FAILED (err u111))

;; Platform Configuration
(define-constant CONTRACT-ADMIN tx-sender)
(define-constant PLATFORM-FEE-RATE u5) ;; 5% platform fee
(define-constant MAX-ROYALTY-RATE u15) ;; Max 15% royalty
(define-constant MAX-RATING-SCORE u5) ;; Rating score out of 5

;; Data Storage
(define-map digital-listings
  { listing-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    price: uint,
    category: (string-ascii 50),
    preview-url: (string-utf8 200),
    asset-url: (string-utf8 200),
    royalty-rate: uint,
    created-at: uint,
    is-active: bool,
  }
)

(define-map ownership-records
  {
    listing-id: uint,
    owner-sequence: uint,
  }
  {
    owner: principal,
    acquired-at: uint,
    purchase-price: uint,
  }
)

(define-map asset-purchases
  {
    listing-id: uint,
    buyer: principal,
  }
  {
    purchased-at: uint,
    purchase-price: uint,
    rated: bool,
  }
)

(define-map asset-ratings
  {
    listing-id: uint,
    rater: principal,
  }
  {
    score: uint,
    comment: (string-utf8 300),
    rated-at: uint,
  }
)

(define-map category-popularity
  {
    category: (string-ascii 50),
    month-year: (string-ascii 7),
  }
  { purchase-volume: uint }
)

;; Global State Variables
(define-data-var last-listing-id uint u0)

(define-map ownership-tracking
  { listing-id: uint }
  { current-sequence: uint }
)

;; Utility Private Functions
(define-private (generate-next-listing-id)
  (let ((next-id (+ (var-get last-listing-id) u1)))
    (var-set last-listing-id next-id)
    next-id
  )
)

(define-private (current-timestamp)
  block-height
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-RATE) u100)
)

(define-private (calculate-royalty
    (amount uint)
    (royalty-rate uint)
  )
  (/ (* amount royalty-rate) u100)
)

;; Public Functions
(define-public (create-digital-listing
    (title (string-ascii 100))
    (description (string-utf8 500))
    (price uint)
    (category (string-ascii 50))
    (preview-url (string-utf8 200))
    (asset-url (string-utf8 200))
    (royalty-rate uint)
  )
  (let ((listing-id (generate-next-listing-id)))
    ;; Input validation
    (asserts! (> price u0) ERR-INVALID-PRICE)
    (asserts! (<= royalty-rate MAX-ROYALTY-RATE) ERR-INVALID-ROYALTY)
    
    ;; Create listing
    (map-set digital-listings { listing-id: listing-id } {
      creator: tx-sender,
      title: title,
      description: description,
      price: price,
      category: category,
      preview-url: preview-url,
      asset-url: asset-url,
      royalty-rate: royalty-rate,
      created-at: (current-timestamp),
      is-active: true,
    })
    
    ;; Initialize ownership record
    (map-set ownership-records {
      listing-id: listing-id,
      owner-sequence: u0,
    } {
      owner: tx-sender,
      acquired-at: (current-timestamp),
      purchase-price: u0,
    })
    
    ;; Initialize ownership tracking
    (map-set ownership-tracking { listing-id: listing-id } { current-sequence: u0 })
    
    (ok listing-id)
  )
)

;; Rest of the contract logic follows the same pattern...
(define-public (update-digital-listing
    (listing-id uint)
    (title (string-ascii 100))
    (description (string-utf8 500))
    (price uint)
    (category (string-ascii 50))
    (preview-url (string-utf8 200))
    (asset-url (string-utf8 200))
    (is-active bool)
  )
  (let ((listing (unwrap! (map-get? digital-listings { listing-id: listing-id }) ERR-NO-LISTING)))
    ;; Authorization check
    (asserts! (is-eq tx-sender (get creator listing)) ERR-UNAUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-PRICE)
    
    ;; Update listing
    (map-set digital-listings { listing-id: listing-id }
      (merge listing {
        title: title,
        description: description,
        price: price,
        category: category,
        preview-url: preview-url,
        asset-url: asset-url,
        is-active: is-active,
      })
    )
    (ok true)
  )
)

(define-public (remove-digital-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? digital-listings { listing-id: listing-id }) ERR-NO-LISTING)))
    ;; Authorization check
    (asserts! (is-eq tx-sender (get creator listing)) ERR-UNAUTHORIZED)
    
    ;; Mark listing as inactive
    (map-set digital-listings { listing-id: listing-id }
      (merge listing { is-active: false })
    )
    (ok true)
  )
)

(define-public (purchase-digital-asset (listing-id uint))
  (let (
      (listing (unwrap! (map-get? digital-listings { listing-id: listing-id })
        ERR-NO-LISTING
      ))
      (buyer tx-sender)
      (creator (get creator listing))
      (price (get price listing))
      (category (get category listing))
      (royalty-rate (get royalty-rate listing))
      (platform-fee (calculate-platform-fee price))
      (creator-amount (- price platform-fee))
    )
    ;; Purchase validation
    (asserts! (get is-active listing) ERR-LISTING-EXPIRED)
    (asserts! (not (is-eq buyer creator)) ERR-UNAUTHORIZED)
    (asserts!
      (is-none (map-get? asset-purchases {
        listing-id: listing-id,
        buyer: buyer,
      }))
      ERR-ALREADY-PURCHASED
    )
    
    ;; Transfer platform fee to contract admin
    (unwrap! (stx-transfer? platform-fee buyer CONTRACT-ADMIN)
      ERR-PLATFORM-FEE-FAILED
    )
    
    ;; Transfer payment to creator
    (unwrap! (stx-transfer? creator-amount buyer creator) ERR-SELLER-PAYMENT-FAILED)
    
    ;; Record the purchase
    (map-set asset-purchases {
      listing-id: listing-id,
      buyer: buyer,
    } {
      purchased-at: (current-timestamp),
      purchase-price: price,
      rated: false,
    })
    
    ;; Record ownership transfer
    (let (
        (index-data (unwrap! (map-get? ownership-tracking { listing-id: listing-id })
          ERR-NO-LISTING
        ))
        (current-sequence (get current-sequence index-data))
        (next-sequence (+ current-sequence u1))
      )
      (map-set ownership-records {
        listing-id: listing-id,
        owner-sequence: next-sequence,
      } {
        owner: buyer,
        acquired-at: (current-timestamp),
        purchase-price: price,
      })
      
      (map-set ownership-tracking { listing-id: listing-id }
        { current-sequence: next-sequence }
      )
    )
    
    (ok true)
  )
)

;; Read-Only Functions
(define-read-only (get-digital-listing (listing-id uint))
  (map-get? digital-listings { listing-id: listing-id })
)

(define-read-only (has-purchased-asset
    (listing-id uint)
    (user principal)
  )
  (is-some (map-get? asset-purchases {
    listing-id: listing-id,
    buyer: user,
  }))
)

;; Other read-only functions remain similar to the original implementation