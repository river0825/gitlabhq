require 'spec_helper'

feature 'Group activity page', feature: true do
  let(:group) { create(:group) }
  let(:path) { activity_group_path(group) }

  context 'when signed in' do
    before do
      user = create(:group_member, :developer, user: create(:user), group: group ).user
      login_as(user)
      visit path
    end

    it_behaves_like "it has an RSS button with current_user's private token"
    it_behaves_like "an autodiscoverable RSS feed with current_user's private token"
  end

  context 'when signed out' do
    before do
      visit path
    end

    it_behaves_like "it has an RSS button without a private token"
    it_behaves_like "an autodiscoverable RSS feed without a private token"
  end
end
