# Detects recurring transactions (subscriptions, bills, paychecks) from a
# family's transaction history. Migration-free: it infers series purely from
# existing entries by grouping on merchant/name and looking for a regular
# cadence between occurrences.
class RecurringSeries
  Series = Data.define(
    :key, :name, :merchant_name, :category_name, :classification,
    :amount, :currency, :cadence, :interval_days, :occurrences,
    :last_date, :next_date, :account_name, :last_amount, :review_reasons
  ) do
    def expense?
      classification == "expense"
    end

    def amount_money
      Money.new(amount, currency)
    end

    def last_amount_money
      Money.new(last_amount, currency)
    end

    def needs_review?
      review_reasons.any?
    end
  end

  # Ordered cadence buckets: label => inclusive day range around the typical interval.
  CADENCES = [
    [ "Weekly",      (5..9) ],
    [ "Biweekly",    (11..18) ],
    [ "Monthly",     (26..35) ],
    [ "Bimonthly",   (55..70) ],
    [ "Quarterly",   (80..100) ],
    [ "Semiannual",  (170..195) ],
    [ "Yearly",      (350..385) ]
  ].freeze

  MIN_OCCURRENCES = 3

  # Minimum deviation from the median amount (as a fraction) before the latest
  # charge is flagged as a price change.
  AMOUNT_CHANGE_THRESHOLD = 0.25

  def initialize(family, lookback_months: 12)
    @family = family
    @since = lookback_months.months.ago.to_date
  end

  # Detected series, soonest upcoming charge first.
  def series
    @series ||= grouped_rows.filter_map { |_key, rows| build_series(rows) }
                            .sort_by { |s| s.next_date }
  end

  def expenses
    series.select(&:expense?)
  end

  def incomes
    series.reject(&:expense?)
  end

  # Series the user should look at: overdue, changed amount, or uncategorized.
  def flagged
    series.select(&:needs_review?).sort_by(&:next_date)
  end

  # Estimated total monthly outflow across detected recurring expenses.
  def monthly_expense_estimate
    total = expenses.sum { |s| monthly_equivalent(s) }
    Money.new(total, @family.currency)
  end

  private

    def grouped_rows
      rows = @family.transactions
                    .visible
                    .standard
                    .where(entries: { date: @since.. })
                    .includes(:merchant, :category, entry: :account)
                    .map do |txn|
        entry = txn.entry
        {
          key: group_key(txn, entry),
          name: entry.name,
          merchant_name: txn.merchant&.name,
          category_name: txn.category&.name,
          amount: entry.amount,
          currency: entry.currency,
          date: entry.date,
          account_name: entry.account&.name
        }
      end

      rows.group_by { |r| r[:key] }
    end

    def group_key(txn, entry)
      return "merchant:#{txn.merchant_id}" if txn.merchant_id.present?

      "name:#{normalize_name(entry.name)}"
    end

    # Collapse trailing identifiers (dates, reference numbers) so the same
    # biller groups together across statements.
    def normalize_name(name)
      name.to_s.downcase.gsub(/[0-9#*]+/, "").squish
    end

    def build_series(rows)
      return nil if rows.size < MIN_OCCURRENCES

      dates = rows.map { |r| r[:date] }.sort
      gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }.reject(&:zero?)
      return nil if gaps.size < MIN_OCCURRENCES - 1

      interval = median(gaps).round
      cadence = cadence_for(interval)
      return nil unless cadence

      # Guard against noisy groups: most gaps should sit near the median.
      consistent = gaps.count { |g| (g - interval).abs <= interval * 0.35 }
      return nil if consistent < (gaps.size * 0.6).ceil

      sample = rows.max_by { |r| r[:date] }
      amount = median(rows.map { |r| r[:amount] })
      last_date = dates.last
      last_amount = sample[:amount]
      next_date = last_date + interval

      Series.new(
        key: sample[:key],
        name: sample[:merchant_name] || sample[:name],
        merchant_name: sample[:merchant_name],
        category_name: sample[:category_name],
        classification: amount.negative? ? "income" : "expense",
        amount: amount.abs,
        currency: sample[:currency],
        cadence: cadence,
        interval_days: interval,
        occurrences: rows.size,
        last_date: last_date,
        next_date: next_date,
        account_name: sample[:account_name],
        last_amount: last_amount.abs,
        review_reasons: review_reasons(
          next_date: next_date,
          interval: interval,
          median_amount: amount.abs,
          last_amount: last_amount.abs,
          category_name: sample[:category_name]
        )
      )
    end

    # Human-readable reasons a series should be reviewed. Empty means "looks fine".
    def review_reasons(next_date:, interval:, median_amount:, last_amount:, category_name:)
      reasons = []

      days_overdue = (Date.current - next_date).to_i
      grace = [ (interval * 0.25).round, 3 ].max
      # Flag a missed/late charge, but not series that ended long ago (likely cancelled).
      if days_overdue > grace && days_overdue <= interval * 2
        reasons << "Expected around #{next_date.strftime("%b %d")} — #{days_overdue} days late"
      end

      if median_amount.positive?
        change = (last_amount - median_amount).abs / median_amount
        if change >= AMOUNT_CHANGE_THRESHOLD
          direction = last_amount > median_amount ? "up" : "down"
          reasons << "Amount #{direction} to #{Money.new(last_amount, @family.currency).format} (usually #{Money.new(median_amount, @family.currency).format})"
        end
      end

      reasons << "No category assigned" if category_name.blank?

      reasons
    end

    def cadence_for(interval_days)
      CADENCES.find { |_label, range| range.cover?(interval_days) }&.first
    end

    def monthly_equivalent(s)
      (s.amount * 30.0 / s.interval_days).round(2)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      if sorted.size.odd?
        sorted[mid]
      else
        (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end
end
