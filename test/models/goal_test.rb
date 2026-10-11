require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "progress percent reflects saved vs target" do
    goal = @family.goals.create!(name: "Vacation", target_amount: 1000, current_amount: 250, currency: "USD")
    assert_equal 25.0, goal.progress_percent
  end

  test "progress percent caps at 100" do
    goal = @family.goals.create!(name: "Fund", target_amount: 1000, current_amount: 1500, currency: "USD")
    assert_equal 100.0, goal.progress_percent
    assert goal.completed?
  end

  test "remaining amount never negative" do
    goal = @family.goals.create!(name: "Fund", target_amount: 1000, current_amount: 1500, currency: "USD")
    assert_equal 0, goal.remaining_amount
  end

  test "requires a positive target amount" do
    goal = @family.goals.new(name: "Bad", target_amount: 0, currency: "USD")
    assert_not goal.valid?
    assert_includes goal.errors[:target_amount], "must be greater than 0"
  end

  test "active and completed scopes" do
    active = @family.goals.create!(name: "A", target_amount: 100, current_amount: 10, currency: "USD")
    done = @family.goals.create!(name: "B", target_amount: 100, current_amount: 100, currency: "USD")

    assert_includes @family.goals.active, active
    assert_includes @family.goals.completed, done
    assert_not_includes @family.goals.active, done
  end

  test "months remaining counts whole months to the target date" do
    goal = @family.goals.new(name: "Trip", target_amount: 1000, target_date: Date.new(2026, 6, 15), currency: "USD")
    assert_equal 5, goal.months_remaining(Date.new(2026, 1, 1))
  end

  test "months remaining is nil without a target date" do
    goal = @family.goals.new(name: "Trip", target_amount: 1000, currency: "USD")
    assert_nil goal.months_remaining
  end

  test "required monthly savings spreads the remaining amount over the months left" do
    goal = @family.goals.new(name: "Trip", target_amount: 1200, current_amount: 200, target_date: Date.new(2026, 6, 1), currency: "USD")
    # 1000 remaining over 5 months = 200/mo
    assert_equal 200, goal.required_monthly_savings(Date.new(2026, 1, 1))
  end

  test "required monthly savings is nil without a deadline or when completed" do
    no_date = @family.goals.new(name: "Open", target_amount: 1000, current_amount: 100, currency: "USD")
    done = @family.goals.new(name: "Done", target_amount: 1000, current_amount: 1000, target_date: Date.current + 1.year, currency: "USD")
    assert_nil no_date.required_monthly_savings
    assert_nil done.required_monthly_savings
  end

  test "on track when monthly savings meet the required pace" do
    goal = @family.goals.new(name: "Trip", target_amount: 1200, current_amount: 200, target_date: Date.new(2026, 6, 1), currency: "USD")
    from = Date.new(2026, 1, 1)
    assert goal.on_track?(250, from)
    assert_not goal.on_track?(150, from)
  end

  test "goals without a deadline are always on track" do
    goal = @family.goals.new(name: "Open", target_amount: 1000, current_amount: 0, currency: "USD")
    assert goal.on_track?(0)
  end
end
