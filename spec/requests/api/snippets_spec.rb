require 'rails_helper'

describe API::Snippets do
  let!(:user) { create(:user) }

  describe 'GET /snippets/' do
    it 'returns snippets available' do
      public_snippet = create(:personal_snippet, :public, author: user)
      private_snippet = create(:personal_snippet, :private, author: user)
      internal_snippet = create(:personal_snippet, :internal, author: user)

      get api("/snippets/", user)

      expect(response).to have_http_status(200)
      expect(response).to include_pagination_headers
      expect(json_response).to be_an Array
      expect(json_response.map { |snippet| snippet['id']} ).to contain_exactly(
        public_snippet.id,
        internal_snippet.id,
        private_snippet.id)
      expect(json_response.last).to have_key('web_url')
      expect(json_response.last).to have_key('raw_url')
    end

    it 'hides private snippets from regular user' do
      create(:personal_snippet, :private)

      get api("/snippets/", user)

      expect(response).to have_http_status(200)
      expect(response).to include_pagination_headers
      expect(json_response).to be_an Array
      expect(json_response.size).to eq(0)
    end
  end

  describe 'GET /snippets/public' do
    let!(:other_user) { create(:user) }
    let!(:public_snippet) { create(:personal_snippet, :public, author: user) }
    let!(:private_snippet) { create(:personal_snippet, :private, author: user) }
    let!(:internal_snippet) { create(:personal_snippet, :internal, author: user) }
    let!(:public_snippet_other) { create(:personal_snippet, :public, author: other_user) }
    let!(:private_snippet_other) { create(:personal_snippet, :private, author: other_user) }
    let!(:internal_snippet_other) { create(:personal_snippet, :internal, author: other_user) }

    it 'returns all snippets with public visibility from all users' do
      get api("/snippets/public", user)

      expect(response).to have_http_status(200)
      expect(response).to include_pagination_headers
      expect(json_response).to be_an Array
      expect(json_response.map { |snippet| snippet['id']} ).to contain_exactly(
        public_snippet.id,
        public_snippet_other.id)
      expect(json_response.map{ |snippet| snippet['web_url']} ).to include(
        "http://localhost/snippets/#{public_snippet.id}",
        "http://localhost/snippets/#{public_snippet_other.id}")
      expect(json_response.map{ |snippet| snippet['raw_url']} ).to include(
        "http://localhost/snippets/#{public_snippet.id}/raw",
        "http://localhost/snippets/#{public_snippet_other.id}/raw")
    end
  end

  describe 'GET /snippets/:id/raw' do
    let(:snippet) { create(:personal_snippet, author: user) }

    it 'returns raw text' do
      get api("/snippets/#{snippet.id}/raw", user)

      expect(response).to have_http_status(200)
      expect(response.content_type).to eq 'text/plain'
      expect(response.body).to eq(snippet.content)
    end

    it 'returns 404 for invalid snippet id' do
      get api("/snippets/1234/raw", user)

      expect(response).to have_http_status(404)
      expect(json_response['message']).to eq('404 Snippet Not Found')
    end
  end

  describe 'POST /snippets/' do
    let(:params) do
      {
        title: 'Test Title',
        file_name: 'test.rb',
        content: 'puts "hello world"',
        visibility: 'public'
      }
    end

    it 'creates a new snippet' do
      expect do
        post api("/snippets/", user), params
      end.to change { PersonalSnippet.count }.by(1)

      expect(response).to have_http_status(201)
      expect(json_response['title']).to eq(params[:title])
      expect(json_response['file_name']).to eq(params[:file_name])
    end

    it 'returns 400 for missing parameters' do
      params.delete(:title)

      post api("/snippets/", user), params

      expect(response).to have_http_status(400)
    end

    context 'when the snippet is spam' do
      def create_snippet(snippet_params = {})
        post api('/snippets', user), params.merge(snippet_params)
      end

      before do
        allow_any_instance_of(AkismetService).to receive(:is_spam?).and_return(true)
      end

      context 'when the snippet is private' do
        it 'creates the snippet' do
          expect { create_snippet(visibility: 'private') }.
            to change { Snippet.count }.by(1)
        end
      end

      context 'when the snippet is public' do
        it 'rejects the shippet' do
          expect { create_snippet(visibility: 'public') }.
            not_to change { Snippet.count }

          expect(response).to have_http_status(400)
          expect(json_response['message']).to eq({ "error" => "Spam detected" })
        end

        it 'creates a spam log' do
          expect { create_snippet(visibility: 'public') }.
            to change { SpamLog.count }.by(1)
        end
      end
    end
  end

  describe 'PUT /snippets/:id' do
    let(:visibility_level) { Snippet::PUBLIC }
    let(:other_user) { create(:user) }
    let(:snippet) do
      create(:personal_snippet, author: user, visibility_level: visibility_level)
    end

    it 'updates snippet' do
      new_content = 'New content'

      put api("/snippets/#{snippet.id}", user), content: new_content

      expect(response).to have_http_status(200)
      snippet.reload
      expect(snippet.content).to eq(new_content)
    end

    it 'returns 404 for invalid snippet id' do
      put api("/snippets/1234", user), title: 'foo'

      expect(response).to have_http_status(404)
      expect(json_response['message']).to eq('404 Snippet Not Found')
    end

    it "returns 404 for another user's snippet" do
      put api("/snippets/#{snippet.id}", other_user), title: 'fubar'

      expect(response).to have_http_status(404)
      expect(json_response['message']).to eq('404 Snippet Not Found')
    end

    it 'returns 400 for missing parameters' do
      put api("/snippets/1234", user)

      expect(response).to have_http_status(400)
    end

    context 'when the snippet is spam' do
      def update_snippet(snippet_params = {})
        put api("/snippets/#{snippet.id}", user), snippet_params
      end

      before do
        allow_any_instance_of(AkismetService).to receive(:is_spam?).and_return(true)
      end

      context 'when the snippet is private' do
        let(:visibility_level) { Snippet::PRIVATE }

        it 'updates the snippet' do
          expect { update_snippet(title: 'Foo') }.
            to change { snippet.reload.title }.to('Foo')
        end
      end

      context 'when the snippet is public' do
        let(:visibility_level) { Snippet::PUBLIC }

        it 'rejects the shippet' do
          expect { update_snippet(title: 'Foo') }.
            not_to change { snippet.reload.title }

          expect(response).to have_http_status(400)
          expect(json_response['message']).to eq({ "error" => "Spam detected" })
        end

        it 'creates a spam log' do
          expect { update_snippet(title: 'Foo') }.
            to change { SpamLog.count }.by(1)
        end
      end

      context 'when a private snippet is made public' do
        let(:visibility_level) { Snippet::PRIVATE }

        it 'rejects the snippet' do
          expect { update_snippet(title: 'Foo', visibility: 'public') }.
            not_to change { snippet.reload.title }
        end

        it 'creates a spam log' do
          expect { update_snippet(title: 'Foo', visibility: 'public') }.
            to change { SpamLog.count }.by(1)
        end
      end
    end
  end

  describe 'DELETE /snippets/:id' do
    let!(:public_snippet) { create(:personal_snippet, :public, author: user) }
    it 'deletes snippet' do
      expect do
        delete api("/snippets/#{public_snippet.id}", user)

        expect(response).to have_http_status(204)
      end.to change { PersonalSnippet.count }.by(-1)
    end

    it 'returns 404 for invalid snippet id' do
      delete api("/snippets/1234", user)

      expect(response).to have_http_status(404)
      expect(json_response['message']).to eq('404 Snippet Not Found')
    end
  end
end
