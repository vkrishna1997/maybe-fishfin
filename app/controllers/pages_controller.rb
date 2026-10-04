class PagesController < ApplicationController
  include Periodable

  skip_authentication only: :redis_configuration_error

  def dashboard
    @balance_sheet = Current.family.balance_sheet
    @accounts = Current.family.accounts.visible.with_attached_logo

    period_param = params[:cashflow_period]
    @cashflow_period = if period_param.present?
      begin
        Period.from_key(period_param)
      rescue Period::InvalidKeyError
        Period.last_30_days
      end
    else
      Period.last_30_days
    end

    family_currency = Current.family.currency
    income_totals = Current.family.income_statement.income_totals(period: @cashflow_period)
    expense_totals = Current.family.income_statement.expense_totals(period: @cashflow_period)

    @cashflow_sankey_data = build_cashflow_sankey_data(income_totals, expense_totals, family_currency)

    @breadcrumbs = [ [ "Home", root_path ], [ "Dashboard", nil ] ]
  end

  def reports
    load_cashflow_overview(params[:cashflow_period])

    @expense_category_totals = ranked_category_totals(@expense_totals)
    @income_category_totals = ranked_category_totals(@income_totals)

    @breadcrumbs = [ [ "Home", root_path ], [ "Reports", nil ] ]
  end

  def cashflow
    load_cashflow_overview(params[:cashflow_period])

    @monthly_cashflow = monthly_cashflow_series(months: 6)

    @breadcrumbs = [ [ "Home", root_path ], [ "Cash Flow", nil ] ]
  end

  def investments
    @investment_accounts = Current.family.accounts.visible
      .where(accountable_type: %w[Investment Crypto])
      .order(balance: :desc)

    @investments_currency = Current.family.currency
    @total_value = @investment_accounts.sum { |a| a.balance.to_d }

    @holdings_rows = aggregated_holdings(@investment_accounts)
    @holdings_total = @holdings_rows.sum { |r| r[:value] }
    @cash_total  = @total_value - @holdings_total
    @total_cost_basis = @holdings_rows.sum { |r| r[:cost_basis] }
    @total_return = @holdings_total - @total_cost_basis

    @allocation_segments = allocation_segments(@holdings_rows, @cash_total)

    @breadcrumbs = [ [ "Home", root_path ], [ "Investments", nil ] ]
  end

  def recurring
    detector = RecurringSeries.new(Current.family)
    @recurring_expenses = detector.expenses
    @recurring_incomes = detector.incomes
    @monthly_expense_estimate = detector.monthly_expense_estimate
    @recurring_currency = Current.family.currency

    @breadcrumbs = [ [ "Home", root_path ], [ "Recurring", nil ] ]
  end

  def forecasting
    income_statement = Current.family.income_statement
    median_income = income_statement.median_income(interval: "month").to_d
    median_expense = income_statement.median_expense(interval: "month").to_d
    default_contribution = [ median_income - median_expense, 0 ].max
    default_expenses = (median_expense * 12).round

    @forecast_assumptions = {
      monthly_contribution: param_decimal(:monthly_contribution, default_contribution),
      annual_growth_rate: param_decimal(:annual_growth_rate, 6.0),
      years: params[:years].present? ? params[:years].to_i.clamp(1, 50) : 30,
      annual_expenses: param_decimal(:annual_expenses, default_expenses)
    }

    @forecast = NetWorthForecast.new(
      Current.family,
      monthly_contribution: @forecast_assumptions[:monthly_contribution],
      annual_growth_rate: @forecast_assumptions[:annual_growth_rate],
      years: @forecast_assumptions[:years],
      annual_expenses: @forecast_assumptions[:annual_expenses]
    )

    @forecasting_currency = Current.family.currency

    @breadcrumbs = [ [ "Home", root_path ], [ "Forecasting", nil ] ]
  end

  def changelog
    @release_notes = github_provider.fetch_latest_release_notes

    # Fallback if no release notes are available
    if @release_notes.nil?
      @release_notes = {
        avatar: "https://github.com/maybe-finance.png",
        username: "maybe-finance",
        name: "Release notes unavailable",
        published_at: Date.current,
        body: "<p>Unable to fetch the latest release notes at this time. Please check back later or visit our <a href='https://github.com/maybe-finance/maybe/releases' target='_blank'>GitHub releases page</a> directly.</p>"
      }
    end

    render layout: "settings"
  end

  def feedback
    render layout: "settings"
  end

  def redis_configuration_error
    render layout: "blank"
  end

  private
    def github_provider
      Provider::Registry.get_provider(:github)
    end

    # Parses a decimal query param, falling back to the given default when the
    # param is blank or not a valid number.
    def param_decimal(key, default)
      raw = params[key]
      return default if raw.blank?

      BigDecimal(raw.to_s)
    rescue ArgumentError
      default
    end

    # Shared cash-flow data for the Reports and Cash Flow tabs: resolves the
    # selected period, income/expense totals, prior-period comparison and sankey.
    def load_cashflow_overview(period_param)
      @accounts = Current.family.accounts.visible

      @cashflow_period = if period_param.present?
        begin
          Period.from_key(period_param)
        rescue Period::InvalidKeyError
          Period.last_30_days
        end
      else
        Period.last_30_days
      end

      income_statement = Current.family.income_statement
      @income_totals = income_statement.income_totals(period: @cashflow_period)
      @expense_totals = income_statement.expense_totals(period: @cashflow_period)

      prior_period = previous_period_for(@cashflow_period)
      if prior_period
        @prior_income_total = income_statement.income_totals(period: prior_period).total
        @prior_expense_total = income_statement.expense_totals(period: prior_period).total
        @comparison_label = @cashflow_period.comparison_label
      end

      @cashflow_sankey_data = build_cashflow_sankey_data(@income_totals, @expense_totals, Current.family.currency)
    end

    # Income/expense/net totals for each of the last `months` calendar months,
    # oldest first, for the Cash Flow over-time chart.
    def monthly_cashflow_series(months: 6)
      income_statement = Current.family.income_statement
      anchor = Date.current.beginning_of_month

      (0...months).to_a.reverse.map do |offset|
        month_start = anchor - offset.months
        period = Period.new(start_date: month_start, end_date: month_start.end_of_month)
        income = income_statement.income_totals(period: period).total.to_f
        expense = income_statement.expense_totals(period: period).total.to_f

        {
          label: month_start.strftime("%b"),
          month: month_start.strftime("%b %Y"),
          income: income,
          expense: expense,
          net: income - expense
        }
      end
    end

    # Current holdings aggregated by security across the given accounts, with a
    # rough cost basis (from avg_cost) so we can show unrealized return.
    def aggregated_holdings(accounts)
      accounts.flat_map { |a| a.current_holdings.to_a }
        .group_by(&:security_id)
        .map do |_security_id, holdings|
          first = holdings.first
          value = holdings.sum { |h| h.amount.to_d }
          cost_basis = holdings.sum { |h| h.qty.to_d * h.avg_cost.amount.to_d }

          {
            name: first.name,
            ticker: first.ticker,
            qty: holdings.sum { |h| h.qty.to_d },
            value: value,
            cost_basis: cost_basis,
            return_amount: value - cost_basis
          }
        end
        .sort_by { |r| -r[:value] }
    end

    # Donut segments for portfolio allocation: top holdings, an "Other" bucket
    # for the long tail, and brokerage cash.
    def allocation_segments(holdings_rows, cash_total, top_n: 6)
      palette = %w[#4da568 #e8603c #e8a33c #3c82e8 #9b3ce8 #e83c9b #3cc6e8 #8a8f98]

      segments = []
      top = holdings_rows.first(top_n)
      rest = holdings_rows[top_n..] || []

      top.each_with_index do |row, i|
        segments << { id: row[:ticker] || row[:name], amount: row[:value].to_f.round(2), color: palette[i % palette.size] }
      end

      if rest.any?
        segments << { id: "Other", amount: rest.sum { |r| r[:value] }.to_f.round(2), color: "#8a8f98" }
      end

      if cash_total.positive?
        segments << { id: "Cash", amount: cash_total.to_f.round(2), color: "#2e9e8f" }
      end

      segments.select { |s| s[:amount] > 0 }
    end

    # Root-level category totals for a classification, non-zero, ranked by spend desc.
    def ranked_category_totals(period_total)
      period_total.category_totals
        .reject { |ct| ct.category.subcategory? }
        .reject { |ct| ct.total.to_d.zero? }
        .sort_by { |ct| -ct.total.to_d }
    end

    # Equal-length window immediately preceding the given period, for comparisons.
    def previous_period_for(period)
      prior_end = period.start_date - 1
      prior_start = prior_end - (period.days - 1)
      Period.new(start_date: prior_start, end_date: prior_end)
    rescue ArgumentError
      nil
    end

    def build_cashflow_sankey_data(income_totals, expense_totals, currency_symbol)
      nodes = []
      links = []
      node_indices = {} # Memoize node indices by a unique key: "type_categoryid"

      # Helper to add/find node and return its index
      add_node = ->(unique_key, display_name, value, percentage, color) {
        node_indices[unique_key] ||= begin
          nodes << { name: display_name, value: value.to_f.round(2), percentage: percentage.to_f.round(1), color: color }
          nodes.size - 1
        end
      }

      total_income_val = income_totals.total.to_f.round(2)
      total_expense_val = expense_totals.total.to_f.round(2)

      # --- Create Central Cash Flow Node ---
      cash_flow_idx = add_node.call("cash_flow_node", "Cash Flow", total_income_val, 0, "var(--color-success)")

      # --- Process Income Side (Top-level categories only) ---
      income_totals.category_totals.each do |ct|
        # Skip subcategories – only include root income categories
        next if ct.category.parent_id.present?

        val = ct.total.to_f.round(2)
        next if val.zero?

        percentage_of_total_income = total_income_val.zero? ? 0 : (val / total_income_val * 100).round(1)

        node_display_name = ct.category.name
        node_color = ct.category.color.presence || Category::COLORS.sample

        current_cat_idx = add_node.call(
          "income_#{ct.category.id}",
          node_display_name,
          val,
          percentage_of_total_income,
          node_color
        )

        links << {
          source: current_cat_idx,
          target: cash_flow_idx,
          value: val,
          color: node_color,
          percentage: percentage_of_total_income
        }
      end

      # --- Process Expense Side (Top-level categories only) ---
      expense_totals.category_totals.each do |ct|
        # Skip subcategories – only include root expense categories to keep Sankey shallow
        next if ct.category.parent_id.present?

        val = ct.total.to_f.round(2)
        next if val.zero?

        percentage_of_total_expense = total_expense_val.zero? ? 0 : (val / total_expense_val * 100).round(1)

        node_display_name = ct.category.name
        node_color = ct.category.color.presence || Category::UNCATEGORIZED_COLOR

        current_cat_idx = add_node.call(
          "expense_#{ct.category.id}",
          node_display_name,
          val,
          percentage_of_total_expense,
          node_color
        )

        links << {
          source: cash_flow_idx,
          target: current_cat_idx,
          value: val,
          color: node_color,
          percentage: percentage_of_total_expense
        }
      end

      # --- Process Surplus ---
      leftover = (total_income_val - total_expense_val).round(2)
      if leftover.positive?
        percentage_of_total_income_for_surplus = total_income_val.zero? ? 0 : (leftover / total_income_val * 100).round(1)
        surplus_idx = add_node.call("surplus_node", "Surplus", leftover, percentage_of_total_income_for_surplus, "var(--color-success)")
        links << { source: cash_flow_idx, target: surplus_idx, value: leftover, color: "var(--color-success)", percentage: percentage_of_total_income_for_surplus }
      end

      # Update Cash Flow and Income node percentages (relative to total income)
      if node_indices["cash_flow_node"]
        nodes[node_indices["cash_flow_node"]][:percentage] = 100.0
      end
      # No primary income node anymore, percentages are on individual income cats relative to total_income_val

      { nodes: nodes, links: links, currency_symbol: Money::Currency.new(currency_symbol).symbol }
    end
end
