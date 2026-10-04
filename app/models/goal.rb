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
end
