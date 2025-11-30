use aiken/collection/list
use aiken/crypto.{Blake2b_224, Hash}
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference, Transaction}

// Represents one part of the tender with cost (in crores) and time (in weeks)
pub type TenderPart {
  part_id: Int,
  min_cost_cr: Int,  // Minimum cost in crores
  max_cost_cr: Int,  // Maximum cost in crores
  min_time_weeks: Int,  // Minimum time in weeks
  max_time_weeks: Int,  // Maximum time in weeks
}

// Government's tender specification with 4 parts
pub type TenderSpec {
  tender_id: ByteArray,
  part1: TenderPart,
  part2: TenderPart,
  part3: TenderPart,
  part4: TenderPart,
  target_avg_cost_time_ratio: Int,  // Target average (cost/time) * 100 for precision
  government_authority: Hash<Blake2b_224, ByteArray>,  // Government's verification key hash
}

// A bidder's proposal for one part
pub type BidPart {
  part_id: Int,
  cost_cr: Int,  // Cost in crores
  time_weeks: Int,  // Time in weeks
}

// Complete bid submission (anonymous - no bidder identity)
pub type BidSubmission {
  bid_hash: ByteArray,  // Hash of bid for uniqueness
  part1_bid: BidPart,
  part2_bid: BidPart,
  part3_bid: BidPart,
  part4_bid: BidPart,
}

pub type Datum {
  tender_spec: TenderSpec,
  submitted_bids: List<BidSubmission>,  // List of all submitted bids
}

pub type Redeemer {
  SubmitBid { bid: BidSubmission }
  SelectTopBids { selected_bid_hashes: List<ByteArray> }
  CloseTender
}

// Calculate cost/time ratio multiplied by 100 for precision
fn calculate_ratio(cost: Int, time: Int) -> Int {
  cost * 100 / time
}

// Validate a single part bid against tender limits
fn validate_part_bid(bid_part: BidPart, tender_part: TenderPart) -> Bool {
  bid_part.part_id == tender_part.part_id && 
  bid_part.cost_cr >= tender_part.min_cost_cr &&
  bid_part.cost_cr <= tender_part.max_cost_cr &&
  bid_part.time_weeks >= tender_part.min_time_weeks &&
  bid_part.time_weeks <= tender_part.max_time_weeks &&
  bid_part.time_weeks > 0  // Prevent division by zero
}

// Validate entire bid submission
fn validate_bid(bid: BidSubmission, tender: TenderSpec) -> Bool {
  let part1_valid = validate_part_bid(bid.part1_bid, tender.part1)
  let part2_valid = validate_part_bid(bid.part2_bid, tender.part2)
  let part3_valid = validate_part_bid(bid.part3_bid, tender.part3)
  let part4_valid = validate_part_bid(bid.part4_bid, tender.part4)
  
  part1_valid && part2_valid && part3_valid && part4_valid
}

// Calculate average cost/time ratio for a bid
fn calculate_avg_ratio(bid: BidSubmission) -> Int {
  let ratio1 = calculate_ratio(bid.part1_bid.cost_cr, bid.part1_bid.time_weeks)
  let ratio2 = calculate_ratio(bid.part2_bid.cost_cr, bid.part2_bid.time_weeks)
  let ratio3 = calculate_ratio(bid.part3_bid.cost_cr, bid.part3_bid.time_weeks)
  let ratio4 = calculate_ratio(bid.part4_bid.cost_cr, bid.part4_bid.time_weeks)
  
  (ratio1 + ratio2 + ratio3 + ratio4) / 4
}

// Map a bid to its hash and average cost/time ratio
pub type BidRatioMapping {
  bid_hash: ByteArray,
  avg_cost_time_ratio: Int,
  part1_ratio: Int,
  part2_ratio: Int,
  part3_ratio: Int,
  part4_ratio: Int,
}

// Create a mapping for a single bid
fn create_bid_mapping(bid: BidSubmission) -> BidRatioMapping {
  BidRatioMapping {
    bid_hash: bid.bid_hash,
    avg_cost_time_ratio: calculate_avg_ratio(bid),
    part1_ratio: calculate_ratio(bid.part1_bid.cost_cr, bid.part1_bid.time_weeks),
    part2_ratio: calculate_ratio(bid.part2_bid.cost_cr, bid.part2_bid.time_weeks),
    part3_ratio: calculate_ratio(bid.part3_bid.cost_cr, bid.part3_bid.time_weeks),
    part4_ratio: calculate_ratio(bid.part4_bid.cost_cr, bid.part4_bid.time_weeks),
  }
}

// Generate mappings for all submitted bids
fn map_all_bids(bids: List<BidSubmission>) -> List<BidRatioMapping> {
  list.map(bids, create_bid_mapping)
}

// Sort mappings by average ratio (ascending - lower is better)
fn sort_by_optimal_ratio(
  mappings: List<BidRatioMapping>,
) -> List<BidRatioMapping> {
  list.sort(
    mappings,
    fn(a, b) {
      if a.avg_cost_time_ratio < b.avg_cost_time_ratio {
        Less
      } else if a.avg_cost_time_ratio > b.avg_cost_time_ratio {
        Greater
      } else {
        Equal
      }
    },
  )
}

// ============ FRONTEND QUERY HELPERS ============

// Dashboard view for Government
pub type GovDashboardView {
  tender_id: ByteArray,
  total_bids: Int,
  all_bid_mappings: List<BidRatioMapping>,
  top_10_bids: List<BidRatioMapping>,
  selected_bids: List<ByteArray>,
  tender_status: TenderStatus,
}

// Dashboard view for Bidder
pub type BidderDashboardView {
  tender_id: ByteArray,
  my_bid_hash: ByteArray,
  my_bid_submission: BidSubmission,
  my_ranking: Int,  // Position among all bids (1 = best)
  total_competitors: Int,
  is_in_top_10: Bool,
  is_selected: Bool,
  tender_status: TenderStatus,
}

// Tender status enum
pub type TenderStatus {
  Open
  UnderReview
  Closed
}

// Get complete government dashboard data
pub fn get_gov_dashboard(
  datum: Datum,
  selected_hashes: List<ByteArray>,
) -> GovDashboardView {
  let all_mappings = map_all_bids(datum.submitted_bids)
  let sorted_mappings = sort_by_optimal_ratio(all_mappings)
  let top_10 = list.take(sorted_mappings, 10)
  
  GovDashboardView {
    tender_id: datum.tender_spec.tender_id,
    total_bids: list.length(datum.submitted_bids),
    all_bid_mappings: sorted_mappings,
    top_10_bids: top_10,
    selected_bids: selected_hashes,
    tender_status: if list.length(selected_hashes) > 0 {
      Closed
    } else if list.length(datum.submitted_bids) > 0 {
      UnderReview
    } else {
      Open
    },
  }
}

// Get bidder's dashboard data by their bid hash
pub fn get_bidder_dashboard(
  datum: Datum,
  my_bid_hash: ByteArray,
  selected_hashes: List<ByteArray>,
) -> Option<BidderDashboardView> {
  // Find bidder's submission
  expect Some(my_bid) =
    list.find(datum.submitted_bids, fn(bid) { bid.bid_hash == my_bid_hash })
  
  // Generate all mappings and sort by optimal ratio
  let all_mappings = map_all_bids(datum.submitted_bids)
  let sorted_mappings = sort_by_optimal_ratio(all_mappings)
  
  // Find bidder's ranking
  let my_ranking = find_ranking(my_bid_hash, sorted_mappings, 1)
  
  // Check if in top 10
  let top_10 = list.take(sorted_mappings, 10)
  let is_in_top_10 =
    list.any(top_10, fn(mapping) { mapping.bid_hash == my_bid_hash })
  
  // Check if selected by government
  let is_selected = list.has(selected_hashes, my_bid_hash)
  
  Some(
    BidderDashboardView {
      tender_id: datum.tender_spec.tender_id,
      my_bid_hash,
      my_bid_submission: my_bid,
      my_ranking,
      total_competitors: list.length(datum.submitted_bids),
      is_in_top_10,
      is_selected,
      tender_status: if list.length(selected_hashes) > 0 {
        Closed
      } else if list.length(datum.submitted_bids) > 0 {
        UnderReview
      } else {
        Open
      },
    },
  )
}

// Helper to find ranking position
fn find_ranking(
  bid_hash: ByteArray,
  sorted_mappings: List<BidRatioMapping>,
  current_rank: Int,
) -> Int {
  when sorted_mappings is {
    [] -> 0
    [first, ..rest] ->
      if first.bid_hash == bid_hash {
        current_rank
      } else {
        find_ranking(bid_hash, rest, current_rank + 1)
      }
  }
}

// Get all bids submitted from a specific address (via bid_hash prefix)
pub fn get_bids_by_address_prefix(
  datum: Datum,
  address_prefix: ByteArray,
) -> List<BidSubmission> {
  list.filter(
    datum.submitted_bids,
    fn(bid) { bytearray.take(bid.bid_hash, bytearray.length(address_prefix)) == address_prefix },
  )
}

// Get tender summary for listing page
pub type TenderSummary {
  tender_id: ByteArray,
  total_bids: Int,
  min_total_cost: Int,  // Sum of all min costs
  max_total_cost: Int,  // Sum of all max costs
  target_ratio: Int,
  is_open: Bool,
}

pub fn get_tender_summary(datum: Datum) -> TenderSummary {
  let total_min = datum.tender_spec.part1.min_cost_cr + 
                  datum.tender_spec.part2.min_cost_cr + 
                  datum.tender_spec.part3.min_cost_cr + 
                  datum.tender_spec.part4.min_cost_cr
  
  let total_max = datum.tender_spec.part1.max_cost_cr + 
                  datum.tender_spec.part2.max_cost_cr + 
                  datum.tender_spec.part3.max_cost_cr + 
                  datum.tender_spec.part4.max_cost_cr
  
  TenderSummary {
    tender_id: datum.tender_spec.tender_id,
    total_bids: list.length(datum.submitted_bids),
    min_total_cost: total_min,
    max_total_cost: total_max,
    target_ratio: datum.tender_spec.target_avg_cost_time_ratio,
    is_open: True,
  }
}

// ============ END FRONTEND QUERY HELPERS ============

// Check if bid is unique (not already submitted)
fn is_unique_bid(bid: BidSubmission, existing_bids: List<BidSubmission>) -> Bool {
  !list.any(existing_bids, fn(existing) { existing.bid_hash == bid.bid_hash })
}

// Verify selected bids are in submitted list
fn verify_selected_bids(
  selected_hashes: List<ByteArray>,
  submitted_bids: List<BidSubmission>,
) -> Bool {
  let valid_count = list.foldr(
    selected_hashes,
    0,
    fn(hash, acc) {
      if list.any(submitted_bids, fn(bid) { bid.bid_hash == hash }) {
        acc + 1
      } else {
        acc
      }
    },
  )
  
  valid_count == list.length(selected_hashes)
}

// Verify bid submission and selection by government
validator government_tender {
  spend(
    datum: Option<Datum>,
    redeemer: Redeemer,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(Datum { tender_spec, submitted_bids }) = datum
    
    when redeemer is {
      // Bidders submit bids anonymously
      SubmitBid { bid } -> {
        // Validate bid against tender specifications
        let bid_valid = validate_bid(bid, tender_spec)
        
        // Ensure bid is unique
        let bid_unique = is_unique_bid(bid, submitted_bids)
        
        // Ensure bid hash is not empty
        let has_valid_hash = bytearray.length(bid.bid_hash) > 0
        
        bid_valid? && bid_unique? && has_valid_hash?
      }
      
      // Government selects top 10 optimal bids
      SelectTopBids { selected_bid_hashes } -> {
        // Must be signed by government authority
        let signed_by_gov = list.has(
          self.extra_signatories,
          tender_spec.government_authority,
        )
        
        // Verify we're selecting at most 10 bids
        let valid_selection_count = list.length(selected_bid_hashes) <= 10
        
        // Verify selected bids exist in submitted bids
        let bids_exist = verify_selected_bids(selected_bid_hashes, submitted_bids)
        
        // Ensure at least one bid is selected
        let has_selection = list.length(selected_bid_hashes) > 0
        
        signed_by_gov? && valid_selection_count? && bids_exist? && has_selection?
      }
      
      // Government closes tender
      CloseTender -> {
        // Must be signed by government authority
        list.has(self.extra_signatories, tender_spec.government_authority)?
      }
    }
  }
}

test submit_valid_bid() {
  let tender_spec = TenderSpec {
    tender_id: "TENDER_001",
    part1: TenderPart {
      part_id: 1,
      min_cost_cr: 10,
      max_cost_cr: 50,
      min_time_weeks: 4,
      max_time_weeks: 20,
    },
    part2: TenderPart {
      part_id: 2,
      min_cost_cr: 15,
      max_cost_cr: 60,
      min_time_weeks: 6,
      max_time_weeks: 24,
    },
    part3: TenderPart {
      part_id: 3,
      min_cost_cr: 20,
      max_cost_cr: 80,
      min_time_weeks: 8,
      max_time_weeks: 30,
    },
    part4: TenderPart {
      part_id: 4,
      min_cost_cr: 25,
      max_cost_cr: 100,
      min_time_weeks: 10,
      max_time_weeks: 40,
    },
    target_avg_cost_time_ratio: 300,
    government_authority: #"00000000000000000000000000000000000000000000000000000000",
  }
  
  let bid = BidSubmission {
    bid_hash: "BID_HASH_001",
    part1_bid: BidPart { part_id: 1, cost_cr: 30, time_weeks: 10 },
    part2_bid: BidPart { part_id: 2, cost_cr: 40, time_weeks: 15 },
    part3_bid: BidPart { part_id: 3, cost_cr: 50, time_weeks: 20 },
    part4_bid: BidPart { part_id: 4, cost_cr: 60, time_weeks: 25 },
  }
  
  let datum = Datum { tender_spec, submitted_bids: [] }
  
  let placeholder_utxo = OutputReference { 
    transaction_id: transaction.placeholder.id, 
    output_index: 0 
  }
  
  government_tender.spend(
    Some(datum),
    SubmitBid { bid },
    placeholder_utxo,
    transaction.placeholder,
  )
}

test select_top_bids() {
  let gov_key = #"00000000000000000000000000000000000000000000000000000000"
  
  let tender_spec = TenderSpec {
    tender_id: "TENDER_001",
    part1: TenderPart { part_id: 1, min_cost_cr: 10, max_cost_cr: 50, min_time_weeks: 4, max_time_weeks: 20 },
    part2: TenderPart { part_id: 2, min_cost_cr: 15, max_cost_cr: 60, min_time_weeks: 6, max_time_weeks: 24 },
    part3: TenderPart { part_id: 3, min_cost_cr: 20, max_cost_cr: 80, min_time_weeks: 8, max_time_weeks: 30 },
    part4: TenderPart { part_id: 4, min_cost_cr: 25, max_cost_cr: 100, min_time_weeks: 10, max_time_weeks: 40 },
    target_avg_cost_time_ratio: 300,
    government_authority: gov_key,
  }
  
  let bid1 = BidSubmission {
    bid_hash: "BID_001",
    part1_bid: BidPart { part_id: 1, cost_cr: 30, time_weeks: 10 },
    part2_bid: BidPart { part_id: 2, cost_cr: 40, time_weeks: 15 },
    part3_bid: BidPart { part_id: 3, cost_cr: 50, time_weeks: 20 },
    part4_bid: BidPart { part_id: 4, cost_cr: 60, time_weeks: 25 },
  }
  
  let datum = Datum { tender_spec, submitted_bids: [bid1] }
  
  let placeholder_utxo = OutputReference { 
    transaction_id: transaction.placeholder.id, 
    output_index: 0 
  }
  
  government_tender.spend(
    Some(datum),
    SelectTopBids { selected_bid_hashes: ["BID_001"] },
    placeholder_utxo,
    Transaction { ..transaction.placeholder, extra_signatories: [gov_key] },
  )
}

test bid_ratio_mapping() {
  let bid1 = BidSubmission {
    bid_hash: "BID_001",
    part1_bid: BidPart { part_id: 1, cost_cr: 30, time_weeks: 10 },
    part2_bid: BidPart { part_id: 2, cost_cr: 40, time_weeks: 15 },
    part3_bid: BidPart { part_id: 3, cost_cr: 50, time_weeks: 20 },
    part4_bid: BidPart { part_id: 4, cost_cr: 60, time_weeks: 25 },
  }
  
  let bid2 = BidSubmission {
    bid_hash: "BID_002",
    part1_bid: BidPart { part_id: 1, cost_cr: 25, time_weeks: 12 },
    part2_bid: BidPart { part_id: 2, cost_cr: 35, time_weeks: 18 },
    part3_bid: BidPart { part_id: 3, cost_cr: 45, time_weeks: 22 },
    part4_bid: BidPart { part_id: 4, cost_cr: 55, time_weeks: 28 },
  }
  
  let mappings = map_all_bids([bid1, bid2])
  
  // Verify mapping created correctly
  let mapping1 = create_bid_mapping(bid1)
  
  // bid1 ratios: 30/10=3.00, 40/15=2.66, 50/20=2.50, 60/25=2.40
  // Average: (300 + 266 + 250 + 240) / 4 = 264
  mapping1.avg_cost_time_ratio == 264 && 
  mapping1.part1_ratio == 300 &&
  list.length(mappings) == 2
}

test bidder_dashboard_query() {
  let tender_spec = TenderSpec {
    tender_id: "TENDER_001",
    part1: TenderPart { part_id: 1, min_cost_cr: 10, max_cost_cr: 50, min_time_weeks: 4, max_time_weeks: 20 },
    part2: TenderPart { part_id: 2, min_cost_cr: 15, max_cost_cr: 60, min_time_weeks: 6, max_time_weeks: 24 },
    part3: TenderPart { part_id: 3, min_cost_cr: 20, max_cost_cr: 80, min_time_weeks: 8, max_time_weeks: 30 },
    part4: TenderPart { part_id: 4, min_cost_cr: 25, max_cost_cr: 100, min_time_weeks: 10, max_time_weeks: 40 },
    target_avg_cost_time_ratio: 300,
    government_authority: #"00000000000000000000000000000000000000000000000000000000",
  }
  
  let bid1 = BidSubmission {
    bid_hash: "BID_001",
    part1_bid: BidPart { part_id: 1, cost_cr: 30, time_weeks: 10 },
    part2_bid: BidPart { part_id: 2, cost_cr: 40, time_weeks: 15 },
    part3_bid: BidPart { part_id: 3, cost_cr: 50, time_weeks: 20 },
    part4_bid: BidPart { part_id: 4, cost_cr: 60, time_weeks: 25 },
  }
  
  let bid2 = BidSubmission {
    bid_hash: "BID_002",
    part1_bid: BidPart { part_id: 1, cost_cr: 25, time_weeks: 12 },
    part2_bid: BidPart { part_id: 2, cost_cr: 35, time_weeks: 18 },
    part3_bid: BidPart { part_id: 3, cost_cr: 45, time_weeks: 22 },
    part4_bid: BidPart { part_id: 4, cost_cr: 55, time_weeks: 28 },
  }
  
  let datum = Datum { tender_spec, submitted_bids: [bid1, bid2] }
  
  // Get bidder dashboard
  expect Some(dashboard) = get_bidder_dashboard(datum, "BID_001", [])
  
  dashboard.my_bid_hash == "BID_001" && 
  dashboard.total_competitors == 2 &&
  dashboard.tender_status == UnderReview
}

test gov_dashboard_query() {
  let tender_spec = TenderSpec {
    tender_id: "TENDER_001",
    part1: TenderPart { part_id: 1, min_cost_cr: 10, max_cost_cr: 50, min_time_weeks: 4, max_time_weeks: 20 },
    part2: TenderPart { part_id: 2, min_cost_cr: 15, max_cost_cr: 60, min_time_weeks: 6, max_time_weeks: 24 },
    part3: TenderPart { part_id: 3, min_cost_cr: 20, max_cost_cr: 80, min_time_weeks: 8, max_time_weeks: 30 },
    part4: TenderPart { part_id: 4, min_cost_cr: 25, max_cost_cr: 100, min_time_weeks: 10, max_time_weeks: 40 },
    target_avg_cost_time_ratio: 300,
    government_authority: #"00000000000000000000000000000000000000000000000000000000",
  }
  
  let bid1 = BidSubmission {
    bid_hash: "BID_001",
    part1_bid: BidPart { part_id: 1, cost_cr: 30, time_weeks: 10 },
    part2_bid: BidPart { part_id: 2, cost_cr: 40, time_weeks: 15 },
    part3_bid: BidPart { part_id: 3, cost_cr: 50, time_weeks: 20 },
    part4_bid: BidPart { part_id: 4, cost_cr: 60, time_weeks: 25 },
  }
  
  let datum = Datum { tender_spec, submitted_bids: [bid1] }
  
  let gov_view = get_gov_dashboard(datum, [])
  
  gov_view.total_bids == 1 && 
  gov_view.tender_status == UnderReview &&
  list.length(gov_view.top_10_bids) == 1
}