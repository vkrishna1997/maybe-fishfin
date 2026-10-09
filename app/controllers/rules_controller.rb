class RulesController < ApplicationController
  include StreamExtensions

  before_action :set_rule, only: [  :edit, :update, :destroy, :apply, :confirm ]

  def index
    @sort_by = params[:sort_by] || "name"
    @direction = params[:direction] || "asc"

    allowed_columns = [ "name", "updated_at" ]
    @sort_by = "name" unless allowed_columns.include?(@sort_by)
    @direction = "asc" unless [ "asc", "desc" ].include?(@direction)

    @rules = Current.family.rules.order(@sort_by => @direction)
    render layout: "settings"
  end

  def new
    @rule = Current.family.rules.build(
      resource_type: params[:resource_type] || "transaction",
    )

    ensure_minimum_fields if prefill_rule_from_context
  end

  def create
    @rule = Current.family.rules.build(rule_params)

    if @rule.save
      redirect_to confirm_rule_path(@rule)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def apply
    @rule.update!(active: true)
    @rule.apply_later(ignore_attribute_locks: true)
    redirect_back_or_to rules_path, notice: "#{@rule.resource_type.humanize} rule activated"
  end

  def confirm
  end

  def edit
  end

  def update
    if @rule.update(rule_params)
      respond_to do |format|
        format.html { redirect_back_or_to rules_path, notice: "Rule updated" }
        format.turbo_stream { stream_redirect_back_or_to rules_path, notice: "Rule updated" }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to rules_path, notice: "Rule deleted"
  end

  def destroy_all
    Current.family.rules.destroy_all
    redirect_to rules_path, notice: "All rules deleted"
  end

  private
    def set_rule
      @rule = Current.family.rules.find(params[:id])
    end

    # Pre-fills the new-rule form from the transaction the user is acting on (or
    # from explicit action/condition query params), mirroring how Monarch/Mint
    # let you "create a rule from this transaction". Returns true if anything
    # was pre-filled.
    def prefill_rule_from_context
      prefilled = false
      prefilled |= prefill_from_transaction(params[:transaction_id]) if params[:transaction_id].present?
      prefilled |= prefill_action_from_params
      prefilled |= prefill_condition_from_params
      prefilled
    end

    def prefill_from_transaction(transaction_id)
      transaction = Current.family.transactions.find_by(id: transaction_id)
      return false unless transaction

      prefilled = false

      if transaction.merchant_id.present?
        @rule.conditions.build(condition_type: "transaction_merchant", operator: "=", value: transaction.merchant_id.to_s)
        prefilled = true
      elsif transaction.entry&.name.present?
        @rule.conditions.build(condition_type: "transaction_name", operator: "like", value: transaction.entry.name)
        prefilled = true
      end

      if transaction.category_id.present?
        @rule.actions.build(action_type: "set_transaction_category", value: transaction.category_id.to_s)
        prefilled = true
      end

      prefilled
    end

    def prefill_action_from_params
      return false if params[:action_type].blank?
      return false if @rule.actions.any? { |a| a.action_type == params[:action_type] }

      @rule.actions.build(action_type: params[:action_type], value: params[:action_value])
      true
    end

    def prefill_condition_from_params
      return false if params[:condition_type].blank?

      @rule.conditions.build(
        condition_type: params[:condition_type],
        operator: params[:condition_operator].presence || "=",
        value: params[:condition_value]
      )
      true
    end

    # Round out a pre-filled form so both the IF and THEN sections show a row.
    def ensure_minimum_fields
      @rule.conditions.build(condition_type: @rule.condition_filters.first.key) if @rule.conditions.empty?
      @rule.actions.build(action_type: @rule.action_executors.first.key) if @rule.actions.empty?
    end

    def rule_params
      params.require(:rule).permit(
        :resource_type, :effective_date, :active, :name,
        conditions_attributes: [
          :id, :condition_type, :operator, :value, :_destroy,
          sub_conditions_attributes: [ :id, :condition_type, :operator, :value, :_destroy ]
        ],
        actions_attributes: [
          :id, :action_type, :value, :_destroy
        ]
      )
    end
end
