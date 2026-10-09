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

    @expense_donut_segments = category_donut_segments(@expense_category_totals)
    @income_donut_segments = category_donut_segments(@income_category_totals)

    @reports_tab = params[:tab].presence || Current.session&.get_preferred_tab("reports_tab") || "cashflow"

    @breadcrumbs = [ [ "Home", root_path ], [ "Reports", nil ] ]
  end

  # Drill-down for the Reports Sankey: transactions for one category (including
  # its subcategories) or a whole classification (all income / all spending)
  # over the currently selected period. Rendered into a Turbo Frame when a
  # Sankey node is clicked.
  def report_transactions
    @report_period = resolve_cashflow_period(params[:cashflow_period])
    @report_currency = Current.family.currency
    @report_cashflow_period_key = params[:cashflow_period]
    @report_classification = params[:classification].to_s.presence

    filters = {
      start_date: @report_period.start_date.to_s,
      end_date: @report_period.end_date.to_s
    }

    if @report_classification.in?(%w[income expense])
      @report_title = @report_classification == "income" ? "All income" : "All spending"
      @report_type_filter = [ @report_classification ]
      filters[:types] = @report_type_filter
    else
      @report_category_name = params[:category].to_s
      @report_title = @report_category_name
      @report_category_names = category_filter_names(@report_category_name)
      filters[:categories] = @report_category_names
    end

    search = Transaction::Search.new(Current.family, filters: filters)

    @report_transactions = search.transactions_scope
                                 .reverse_chronological
                                 .includes({ entry: :account }, :category, :merchant)
                                 .limit(500)
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
      annual_expenses: param_decimal(:annual_expenses, default_expenses),
      current_age: params[:current_age].present? ? params[:current_age].to_i.clamp(0, 120) : nil
    }

    @forecast = NetWorthForecast.new(
      Current.family,
      monthly_contribution: @forecast_assumptions[:monthly_contribution],
      annual_growth_rate: @forecast_assumptions[:annual_growth_rate],
      annual_expenses: @forecast_assumptions[:annual_expenses],
      current_age: @forecast_assumptions[:current_age]
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

      @cashflow_period = resolve_cashflow_period(period_param)

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

    # Resolves the cash-flow period from a period key, defaulting to the last
    # 30 days when absent or invalid.
    def resolve_cashflow_period(period_param)
      if period_param.present?
        begin
          Period.from_key(period_param)
        rescue Period::InvalidKeyError
          Period.last_30_days
        end
      else
        Period.last_30_days
      end
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

    # Donut segments ({id, label, amount, color}) for a ranked list of category
    # totals. `id` is a selector-safe slug; `label` carries the display name.
    def category_donut_segments(category_totals)
      category_totals.each_with_index.filter_map do |ct, index|
        amount = ct.total.to_f.round(2)
        next if amount <= 0

        {
          id: "seg#{index}",
          label: ct.category.name,
          amount: amount,
          color: ct.category.color.presence || Category::UNCATEGORIZED_COLOR
        }
      end
    end

    # A category name plus the names of its subcategories, so a drill-down
    # captures every transaction the (rolled-up) Sankey node represents.
    def category_filter_names(name)
      category = Current.family.categories.find_by(name: name)
      return [ name ] if category.nil?

      [ name ] + category.subcategories.pluck(:name)
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
      add_node = ->(unique_key, display_name, value, percentage, color, meta = {}) {
        node_indices[unique_key] ||= begin
          nodes << { name: display_name, value: value.to_f.round(2), percentage: percentage.to_f.round(1), color: color }.merge(meta)
          nodes.size - 1
        end
      }

      total_income_val = income_totals.total.to_f.round(2)
      total_expense_val = expense_totals.total.to_f.round(2)

      # --- Create Central Cash Flow Node ---
      cash_flow_idx = add_node.call("cash_flow_node", "Cash Flow", total_income_val, 0, "var(--color-success)", { node_type: "cash_flow", classification: "income" })

      # Processes one classification side into up-to-4-level flows:
      #   income:  subcategory -> parent -> Cash Flow
      #   expense: Cash Flow -> parent -> subcategory
      # A parent that also has its own direct transactions gets an "· Other"
      # leaf so the flows into/out of it stay balanced.
      process_side = ->(period_totals, side, side_total, default_color) {
        children_by_parent = Hash.new { |h, k| h[k] = [] }
        period_totals.category_totals.each do |ct|
          children_by_parent[ct.category.parent_id] << ct if ct.category.parent_id.present?
        end

        period_totals.category_totals.each do |ct|
          next if ct.category.parent_id.present? # roots only in the outer loop

          parent_val = ct.total.to_f.round(2)
          next if parent_val.zero?

          parent_pct = side_total.zero? ? 0 : (parent_val / side_total * 100).round(1)
          parent_color = ct.category.color.presence || default_color

          parent_idx = add_node.call(
            "#{side}_#{ct.category.id}",
            ct.category.name,
            parent_val,
            parent_pct,
            parent_color,
            { category_name: ct.category.name, node_type: side.to_s }
          )

          if side == :income
            links << { source: parent_idx, target: cash_flow_idx, value: parent_val, color: parent_color, percentage: parent_pct }
          else
            links << { source: cash_flow_idx, target: parent_idx, value: parent_val, color: parent_color, percentage: parent_pct }
          end

          # --- 4th level: subcategories of this parent ---
          children = children_by_parent[ct.category.id].select { |c| c.total.to_f.round(2).positive? }
          children_sum = 0

          children.each do |cct|
            child_val = cct.total.to_f.round(2)
            children_sum += child_val
            child_pct = parent_val.zero? ? 0 : (child_val / parent_val * 100).round(1)
            child_color = cct.category.color.presence || parent_color

            child_idx = add_node.call(
              "#{side}_#{cct.category.id}",
              cct.category.name,
              child_val,
              child_pct,
              child_color,
              { category_name: cct.category.name, node_type: side.to_s }
            )

            if side == :income
              links << { source: child_idx, target: parent_idx, value: child_val, color: child_color, percentage: child_pct }
            else
              links << { source: parent_idx, target: child_idx, value: child_val, color: child_color, percentage: child_pct }
            end
          end

          # Parent's own direct spend/earnings (not attributed to a subcategory).
          remainder = (parent_val - children_sum).round(2)
          next unless children.any? && remainder.positive?

          remainder_pct = parent_val.zero? ? 0 : (remainder / parent_val * 100).round(1)
          other_idx = add_node.call(
            "#{side}_#{ct.category.id}_other",
            "#{ct.category.name} · Other",
            remainder,
            remainder_pct,
            parent_color,
            { node_type: side.to_s }
          )

          if side == :income
            links << { source: other_idx, target: parent_idx, value: remainder, color: parent_color, percentage: remainder_pct }
          else
            links << { source: parent_idx, target: other_idx, value: remainder, color: parent_color, percentage: remainder_pct }
          end
        end
      }

      process_side.call(income_totals, :income, total_income_val, Category::COLORS.sample)
      process_side.call(expense_totals, :expense, total_expense_val, Category::UNCATEGORIZED_COLOR)

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
