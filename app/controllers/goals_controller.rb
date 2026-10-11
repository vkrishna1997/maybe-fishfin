class GoalsController < ApplicationController
  before_action :set_goal, only: %i[edit update destroy]

  TRAILING_MONTHS = 3

  def index
    @goals = Current.family.goals.ordered
    @total_target = @goals.sum { |g| g.target_amount.to_d }
    @total_saved = @goals.sum { |g| g.current_amount.to_d }
    # Factual month-to-date net savings, shown as-is on the summary tile.
    @actual_savings = current_month_surplus
    # Signal that drives the on-track badge: a trailing average of actual
    # completed-month surplus, which smooths out lumpy income / mid-month noise.
    @monthly_savings = average_monthly_savings
    @savings_months = active_months.size
    @savings_basis = @savings_months >= 2 ? :trailing : :current
    @projected_savings = projected_month_end_savings
    @goals_currency = Current.family.currency
    @breadcrumbs = [ [ "Home", root_path ], [ "Goals", nil ] ]
  end

  def new
    @goal = Current.family.goals.new(currency: Current.family.currency, color: Goal::COLORS.sample)
  end

  def create
    @goal = Current.family.goals.new(goal_params)
    @goal.currency ||= Current.family.currency

    if @goal.save
      redirect_to goals_path, notice: "Goal created"
    else
      redirect_to goals_path, alert: @goal.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @goal.update(goal_params)
      redirect_to goals_path, notice: "Goal updated"
    else
      redirect_to goals_path, alert: @goal.errors.full_messages.to_sentence
    end
  end

  def destroy
    @goal.destroy!
    redirect_to goals_path, notice: "Goal deleted"
  end

  private

    def set_goal
      @goal = Current.family.goals.find(params[:id])
    end

    def income_statement
      @income_statement ||= Current.family.income_statement
    end

    # Net savings (income minus expenses) for an arbitrary period.
    def period_surplus(period)
      income = income_statement.income_totals(period: period).total.to_d
      expense = income_statement.expense_totals(period: period).total.to_d
      income - expense
    end

    # Net amount saved so far this calendar month.
    def current_month_surplus
      period_surplus(Period.current_month)
    end

    # Net savings for each of the last few COMPLETED calendar months, flagged by
    # whether the month had any activity so empty history can be excluded.
    def trailing_months
      @trailing_months ||= TRAILING_MONTHS.times.map do |i|
        month = Date.current.beginning_of_month - (i + 1).months
        period = Period.custom(start_date: month.beginning_of_month, end_date: month.end_of_month)
        income = income_statement.income_totals(period: period).total.to_d
        expense = income_statement.expense_totals(period: period).total.to_d
        { surplus: income - expense, active: !(income.zero? && expense.zero?) }
      end
    end

    def active_months
      @active_months ||= trailing_months.select { |m| m[:active] }
    end

    # Average actual net savings over recent completed months. Falls back to the
    # current month-to-date when there isn't enough history to be meaningful.
    def average_monthly_savings
      return current_month_surplus if active_months.size < 2

      active_months.sum { |m| m[:surplus] } / active_months.size
    end

    # Blends month-to-date actuals with the recent monthly baseline: early in the
    # month this leans on history, later in the month on actuals.
    def projected_month_end_savings
      today = Date.current
      fraction_remaining = 1 - (today.day.to_f / today.end_of_month.day)
      current_month_surplus + (fraction_remaining * average_monthly_savings)
    end

    def goal_params
      params.require(:goal).permit(:name, :target_amount, :current_amount, :target_date, :color)
    end
end
