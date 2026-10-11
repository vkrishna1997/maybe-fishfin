class Goal < ApplicationRecord
  include Monetizable

  belongs_to :family

  COLORS = %w[#4da568 #e99537 #db5a54 #4376c7 #9b59b6 #1abc9c].freeze

  validates :name, :target_amount, :currency, presence: true
  validates :target_amount, numericality: { greater_than: 0 }
  validates :current_amount, numericality: { greater_than_or_equal_to: 0 }

  monetize :target_amount, :current_amount

  scope :active, -> { where("current_amount < target_amount") }
  scope :completed, -> { where("current_amount >= target_amount") }
  scope :ordered, -> { order(Arel.sql("current_amount >= target_amount"), target_date: :asc, created_at: :asc) }

  def progress_percent
    return 100.0 if target_amount.to_d.zero?

    [ (current_amount.to_d / target_amount.to_d * 100).to_f, 100.0 ].min.round(1)
  end

  def completed?
    current_amount.to_d >= target_amount.to_d
  end

  def remaining_amount
    [ target_amount.to_d - current_amount.to_d, 0 ].max
  end

  def remaining_money
    Money.new(remaining_amount, currency)
  end

  # Whole months from +from+ until the target date (0 when the target is this
  # month or already past). Nil when the goal has no target date.
  def months_remaining(from = Date.current)
    return nil if target_date.blank?

    months = (target_date.year - from.year) * 12 + (target_date.month - from.month)
    months -= 1 if target_date.day < from.day
    [ months, 0 ].max
  end

  # Amount that must be set aside each month to hit the target by its date.
  # Nil when there's no deadline or the goal is already met.
  def required_monthly_savings(from = Date.current)
    return nil if target_date.blank? || completed?

    months = [ months_remaining(from), 1 ].max
    remaining_amount / months
  end

  def required_monthly_savings_money(from = Date.current)
    amount = required_monthly_savings(from)
    amount && Money.new(amount, currency)
  end

  # Whether the family's actual savings this month keep the goal on pace.
  # Goals without a deadline (or already met) are always considered on track.
  def on_track?(monthly_savings, from = Date.current)
    required = required_monthly_savings(from)
    return true if required.nil?

    monthly_savings.to_d >= required
  end
end
