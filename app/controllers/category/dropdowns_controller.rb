class Category::DropdownsController < ApplicationController
  before_action :set_from_params

  def show
    @categories = categories_scope.to_a.excluding(@selected_category).prepend(@selected_category).compact
  end

  private
    def set_from_params
      if params[:category_id].present?
        @selected_category = categories_scope.find(params[:category_id])
      end

      if params[:transaction_id].present?
        @transaction = Current.family.transactions.find(params[:transaction_id])
      end

      @entry_ids = Array(params[:entry_ids]).reject(&:blank?)
      @return_to_top = ActiveModel::Type::Boolean.new.cast(params[:return_to_top])
    end

    def categories_scope
      Current.family.categories.alphabetically
    end
end
