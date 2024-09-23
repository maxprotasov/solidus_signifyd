module Models::SpreeSignifyd::Spree::OrderDecorator
  def self.prepended(base)
    base.include SpreeSignifyd::OrderConcerns
  end

  ::Spree::Order.prepend self
end
