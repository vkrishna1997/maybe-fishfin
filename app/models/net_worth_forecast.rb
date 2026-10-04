# Projects a family's net worth forward and estimates financial independence
# (FI) timing using the 4% rule. Migration-free: it seeds from the current
# balance sheet and cash-flow history and applies simple monthly compounding.
class NetWorthForecast
  YearPoint = Data.define(:year, :date, :net_worth) do
    def net_worth_money(currency)
      Money.new(net_worth, currency)
    end
  end

  SAFE_WITHDRAWAL_RATE = 0.04

  def initialize(family, monthly_contribution:, annual_growth_rate:, years:, annual_expenses: nil)
    @family = family
    @currency = family.currency
    @starting_net_worth = family.balance_sheet.net_worth.to_f
    @monthly_contribution = monthly_contribution.to_f
    @annual_growth_rate = annual_growth_rate.to_f
    @years = years.to_i
    @annual_expenses = annual_expenses&.to_f
  end

  attr_reader :currency, :starting_net_worth, :monthly_contribution, :annual_growth_rate, :years

  def monthly_rate
    (@annual_growth_rate / 100.0) / 12.0
  end

  # One YearPoint per year from 0 (today) through the horizon.
  def series
    @series ||= begin
      points = [ YearPoint.new(0, Date.current, @starting_net_worth) ]
      net_worth = @starting_net_worth

      (1..@years).each do |year|
        12.times { net_worth = grow_one_month(net_worth) }
        points << YearPoint.new(year, Date.current + year.years, net_worth)
      end

      points
    end
  end

  def ending_net_worth
    series.last.net_worth
  end

  # Nest egg required to cover annual expenses at a 4% withdrawal rate.
  def fi_number
    return nil if @annual_expenses.nil? || @annual_expenses <= 0

    @annual_expenses / SAFE_WITHDRAWAL_RATE
  end

  # Months until projected net worth first covers the FI number, or nil if it
  # is not reached within the horizon.
  def months_to_fi
    target = fi_number
    return nil if target.nil?
    return 0 if @starting_net_worth >= target

    net_worth = @starting_net_worth

    (1..(@years * 12)).each do |month|
      net_worth = grow_one_month(net_worth)
      return month if net_worth >= target
    end

    nil
  end

  def fi_date
    months = months_to_fi
    months && (Date.current >> months)
  end

  def fi_reached_within_horizon?
    !months_to_fi.nil?
  end

  def money(value)
    Money.new(value || 0, @currency)
  end

  private

    # Advances one month. Growth is applied only to the positive (investable)
    # portion of net worth — debt is not assumed to compound at the market
    # return rate — while contributions always add to net worth.
    def grow_one_month(net_worth)
      growth_base = [ net_worth, 0.0 ].max
      net_worth + (growth_base * monthly_rate) + @monthly_contribution
    end
end
