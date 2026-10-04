class GoalsController < ApplicationController
  before_action :set_goal, only: %i[edit update destroy]

  def index
    @goals = Current.family.goals.ordered
    @total_target = @goals.sum { |g| g.target_amount.to_d }
    @total_saved = @goals.sum { |g| g.current_amount.to_d }
    @monthly_savings = current_month_surplus
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

    # Net amount saved so far this calendar month (income minus expenses).
    def current_month_surplus
      statement = Current.family.income_statement
      income = statement.income_totals(period: Period.current_month).total.to_d
      expense = statement.expense_totals(period: Period.current_month).total.to_d
      income - expense
    end

    def goal_params
      params.require(:goal).permit(:name, :target_amount, :current_amount, :target_date, :color)
    end
end
