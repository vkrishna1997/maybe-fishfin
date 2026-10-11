# Suggests categories for uncategorized transactions based on the family's own
# history. For each uncategorized transaction it looks for a dominant category
# previously used for the same merchant (preferred) or the same description, and
# only suggests a category whose classification (income/expense) matches.
#
# This is a deterministic, always-available complement to the AI auto-categorizer
# (which requires an LLM provider).
class Family::CategorySuggester
  MAX_SUGGESTIONS = 20
  CANDIDATE_SCAN_LIMIT = 200

  def initialize(family)
    @family = family
  end

  # Returns an array of { transaction:, category: } for uncategorized
  # transactions that have a confident historical match.
  def suggestions(limit: MAX_SUGGESTIONS)
    candidates = uncategorized_transactions
    return [] if candidates.empty?

    merchant_map = top_category_by_merchant
    name_map = top_category_by_name
    return [] if merchant_map.empty? && name_map.empty?

    results = []
    candidates.each do |txn|
      category = pick_category(txn, merchant_map, name_map)
      next unless category

      results << { transaction: txn, category: category }
      break if results.size >= limit
    end
    results
  end

  private
    attr_reader :family

    def uncategorized_transactions
      family.transactions
            .where(category_id: nil)
            .enrichable(:category_id)
            .visible
            .where(kind: %w[standard one_time])
            .includes(:merchant, entry: :account)
            .order("entries.date DESC")
            .limit(CANDIDATE_SCAN_LIMIT)
            .to_a
    end

    def categorized_scope
      family.transactions.where.not(category_id: nil)
    end

    # { merchant_id => category_id } for the most frequently used category.
    def top_category_by_merchant
      counts = categorized_scope.where.not(merchant_id: nil)
                                .group(:merchant_id, :category_id)
                                .count
      most_frequent(counts)
    end

    # { downcased_description => category_id } for the most frequently used category.
    def top_category_by_name
      counts = categorized_scope.joins(:entry)
                                .group(Arel.sql("LOWER(entries.name)"), :category_id)
                                .count
      most_frequent(counts)
    end

    # Reduce a { [key, category_id] => count } hash to { key => winning_category_id }.
    def most_frequent(counts)
      best = {}
      counts.each do |(key, category_id), count|
        next if key.blank?

        if best[key].nil? || count > best[key][1]
          best[key] = [ category_id, count ]
        end
      end
      best.transform_values(&:first)
    end

    def pick_category(txn, merchant_map, name_map)
      category_id = (txn.merchant_id && merchant_map[txn.merchant_id]) ||
                    name_map[txn.entry.name.to_s.downcase]
      return nil unless category_id

      category = categories_by_id[category_id]
      return nil unless category
      return nil unless category.classification == txn.entry.classification

      category
    end

    def categories_by_id
      @categories_by_id ||= family.categories.index_by(&:id)
    end
end
