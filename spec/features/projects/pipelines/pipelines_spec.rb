require 'spec_helper'

describe 'Pipelines', :feature, :js do
  include WaitForVueResource

  let(:project) { create(:empty_project) }

  context 'when user is logged in' do
    let(:user) { create(:user) }

    before do
      login_as(user)
      project.team << [user, :developer]
    end

    describe 'GET /:project/pipelines' do
      let(:project) { create(:project) }

      let!(:pipeline) do
        create(
          :ci_empty_pipeline,
          project: project,
          ref: 'master',
          status: 'running',
          sha: project.commit.id,
        )
      end

      context 'scope' do
        before do
          create(:ci_empty_pipeline, status: 'pending', project: project, sha: project.commit.id, ref: 'master')
          create(:ci_empty_pipeline, status: 'running', project: project, sha: project.commit.id, ref: 'master')
          create(:ci_empty_pipeline, status: 'created', project: project, sha: project.commit.id, ref: 'master')
          create(:ci_empty_pipeline, status: 'success', project: project, sha: project.commit.id, ref: 'master')
        end

        [:all, :running, :pending, :finished, :branches].each do |scope|
          context "when displaying #{scope}" do
            before do
              visit_project_pipelines(scope: scope)
            end

            it 'contains pipeline commit short SHA' do
              expect(page).to have_content(pipeline.short_sha)
            end

            it 'contains branch name' do
              expect(page).to have_content(pipeline.ref)
            end
          end
        end
      end

      context 'header tabs' do
        before do
          visit namespace_project_pipelines_path(project.namespace, project)
          wait_for_vue_resource
        end

        it 'shows a tab for All pipelines and count' do
          expect(page.find('.js-pipelines-tab-all a').text).to include('All')
          expect(page.find('.js-pipelines-tab-all .badge').text).to include('1')
        end

        it 'shows a tab for Pending pipelines and count' do
          expect(page.find('.js-pipelines-tab-pending a').text).to include('Pending')
          expect(page.find('.js-pipelines-tab-pending .badge').text).to include('0')
        end

        it 'shows a tab for Running pipelines and count' do
          expect(page.find('.js-pipelines-tab-running a').text).to include('Running')
          expect(page.find('.js-pipelines-tab-running .badge').text).to include('1')
        end

        it 'shows a tab for Finished pipelines and count' do
          expect(page.find('.js-pipelines-tab-finished a').text).to include('Finished')
          expect(page.find('.js-pipelines-tab-finished .badge').text).to include('0')
        end

        it 'shows a tab for Branches' do
          expect(page.find('.js-pipelines-tab-branches a').text).to include('Branches')
        end

        it 'shows a tab for Tags' do
          expect(page.find('.js-pipelines-tab-tags a').text).to include('Tags')
        end
      end

      context 'when pipeline is cancelable' do
        let!(:build) do
          create(:ci_build, pipeline: pipeline,
                            stage: 'test',
                            commands: 'test')
        end

        before do
          build.run
          visit_project_pipelines
        end

        it 'indicates that pipeline can be canceled' do
          expect(page).to have_selector('.js-pipelines-cancel-button')
          expect(page).to have_selector('.ci-running')
        end

        context 'when canceling' do
          before do
            find('.js-pipelines-cancel-button').click
            wait_for_vue_resource
          end

          it 'indicated that pipelines was canceled' do
            expect(page).not_to have_selector('.js-pipelines-cancel-button')
            expect(page).to have_selector('.ci-canceled')
          end
        end
      end

      context 'when pipeline is retryable' do
        let!(:build) do
          create(:ci_build, pipeline: pipeline,
                            stage: 'test',
                            commands: 'test')
        end

        before do
          build.drop
          visit_project_pipelines
        end

        it 'indicates that pipeline can be retried' do
          expect(page).to have_selector('.js-pipelines-retry-button')
          expect(page).to have_selector('.ci-failed')
        end

        context 'when retrying' do
          before do
            find('.js-pipelines-retry-button').click
            wait_for_vue_resource
          end

          it 'shows running pipeline that is not retryable' do
            expect(page).not_to have_selector('.js-pipelines-retry-button')
            expect(page).to have_selector('.ci-running')
          end
        end
      end

      context 'when pipeline has configuration errors' do
        let(:pipeline) do
          create(:ci_pipeline, :invalid, project: project)
        end

        before { visit_project_pipelines }

        it 'contains badge that indicates errors' do
          expect(page).to have_content 'yaml invalid'
        end

        it 'contains badge with tooltip which contains error' do
          expect(pipeline).to have_yaml_errors
          expect(page).to have_selector(
            %Q{span[data-original-title="#{pipeline.yaml_errors}"]})
        end
      end

      context 'with manual actions' do
        let!(:manual) do
          create(:ci_build, :manual,
            pipeline: pipeline,
            name: 'manual build',
            stage: 'test',
            commands: 'test')
        end

        before { visit_project_pipelines }

        it 'has a dropdown with play button' do
          expect(page).to have_selector('.dropdown-toggle.btn.btn-default .icon-play')
        end

        it 'has link to the manual action' do
          find('.js-pipeline-dropdown-manual-actions').click

          expect(page).to have_button('manual build')
        end

        context 'when manual action was played' do
          before do
            find('.js-pipeline-dropdown-manual-actions').click
            click_button('manual build')
          end

          it 'enqueues manual action job' do
            expect(page).to have_selector('.js-pipeline-dropdown-manual-actions:disabled')
          end
        end
      end

      context 'for generic statuses' do
        context 'when running' do
          let!(:running) do
            create(:generic_commit_status,
              status: 'running',
              pipeline: pipeline,
              stage: 'test')
          end

          before { visit_project_pipelines }

          it 'is cancelable' do
            expect(page).to have_selector('.js-pipelines-cancel-button')
          end

          it 'has pipeline running' do
            expect(page).to have_selector('.ci-running')
          end

          context 'when canceling' do
            before { find('.js-pipelines-cancel-button').trigger('click') }

            it 'indicates that pipeline was canceled' do
              expect(page).not_to have_selector('.js-pipelines-cancel-button')
              expect(page).to have_selector('.ci-canceled')
            end
          end
        end

        context 'when failed' do
          let!(:status) do
            create(:generic_commit_status, :pending,
              pipeline: pipeline,
              stage: 'test')
          end

          before do
            status.drop
            visit_project_pipelines
          end

          it 'is not retryable' do
            expect(page).not_to have_selector('.js-pipelines-retry-button')
          end

          it 'has failed pipeline' do
            expect(page).to have_selector('.ci-failed')
          end
        end
      end

      context 'downloadable pipelines' do
        context 'with artifacts' do
          let!(:with_artifacts) do
            create(:ci_build, :artifacts, :success,
              pipeline: pipeline,
              name: 'rspec tests',
              stage: 'test')
          end

          before { visit_project_pipelines }

          it 'has artifats' do
            expect(page).to have_selector('.build-artifacts')
          end

          it 'has artifacts download dropdown' do
            find('.js-pipeline-dropdown-download').click

            expect(page).to have_link(with_artifacts.name)
          end

          it 'has download attribute on download links' do
            find('.js-pipeline-dropdown-download').click
            expect(page).to have_selector('a', text: 'Download')
            page.all('.build-artifacts a', text: 'Download').each do |link|
              expect(link[:download]).to eq ''
            end
          end
        end

        context 'with artifacts expired' do
          let!(:with_artifacts_expired) do
            create(:ci_build, :artifacts_expired, :success,
              pipeline: pipeline,
              name: 'rspec',
              stage: 'test')
          end

          before { visit_project_pipelines }

          it { expect(page).not_to have_selector('.build-artifacts') }
        end

        context 'without artifacts' do
          let!(:without_artifacts) do
            create(:ci_build, :success,
              pipeline: pipeline,
              name: 'rspec',
              stage: 'test')
          end

          before { visit_project_pipelines }

          it { expect(page).not_to have_selector('.build-artifacts') }
        end
      end

      context 'mini pipeline graph' do
        let!(:build) do
          create(:ci_build, :pending, pipeline: pipeline,
                                      stage: 'build',
                                      name: 'build')
        end

        before { visit_project_pipelines }

        it 'should render a mini pipeline graph' do
          expect(page).to have_selector('.js-mini-pipeline-graph')
          expect(page).to have_selector('.js-builds-dropdown-button')
        end

        context 'when clicking a stage badge' do
          it 'should open a dropdown' do
            find('.js-builds-dropdown-button').trigger('click')

            expect(page).to have_link build.name
          end

          it 'should be possible to cancel pending build' do
            find('.js-builds-dropdown-button').trigger('click')
            find('a.js-ci-action-icon').trigger('click')

            expect(page).to have_content('canceled')
            expect(build.reload).to be_canceled
          end
        end

        context 'dropdown jobs list' do
          it 'should keep the dropdown open when the user ctr/cmd + clicks in the job name' do
            find('.js-builds-dropdown-button').trigger('click')

            execute_script('var e = $.Event("keydown", { keyCode: 64 }); $("body").trigger(e);')

            find('.mini-pipeline-graph-dropdown-item').trigger('click')

            expect(page).to have_selector('.js-ci-action-icon')
          end
        end
      end

      context 'with pagination' do
        before do
          allow(Ci::Pipeline).to receive(:default_per_page).and_return(1)
          create(:ci_empty_pipeline,  project: project)
        end

        it 'should render pagination' do
          visit namespace_project_pipelines_path(project.namespace, project)
          wait_for_vue_resource

          expect(page).to have_selector('.gl-pagination')
        end

        it 'should render second page of pipelines' do
          visit namespace_project_pipelines_path(project.namespace, project, page: '2')
          wait_for_vue_resource

          expect(page).to have_selector('.gl-pagination .page', count: 2)
        end
      end
    end

    describe 'POST /:project/pipelines' do
      let(:project) { create(:project) }

      before do
        visit new_namespace_project_pipeline_path(project.namespace, project)
      end

      context 'for valid commit', js: true do
        before do
          click_button project.default_branch

          page.within '.dropdown-menu' do
            click_link 'master'
          end
        end

        context 'with gitlab-ci.yml' do
          before { stub_ci_pipeline_to_return_yaml_file }

          it 'creates a new pipeline' do
            expect { click_on 'Create pipeline' }
              .to change { Ci::Pipeline.count }.by(1)
          end
        end

        context 'without gitlab-ci.yml' do
          before { click_on 'Create pipeline' }

          it { expect(page).to have_content('Missing .gitlab-ci.yml file') }
        end
      end
    end

    describe 'Create pipelines' do
      let(:project) { create(:project) }

      before do
        visit new_namespace_project_pipeline_path(project.namespace, project)
      end

      describe 'new pipeline page' do
        it 'has field to add a new pipeline' do
          expect(page).to have_selector('.js-branch-select')
          expect(find('.js-branch-select')).to have_content project.default_branch
          expect(page).to have_content('Create for')
        end
      end

      describe 'find pipelines' do
        it 'shows filtered pipelines', js: true do
          click_button project.default_branch

          page.within '.dropdown-menu' do
            find('.dropdown-input-field').native.send_keys('fix')

            page.within '.dropdown-content' do
              expect(page).to have_content('fix')
            end
          end
        end
      end
    end
  end

  context 'when user is not logged in' do
    before do
      visit namespace_project_pipelines_path(project.namespace, project)
    end

    context 'when project is public' do
      let(:project) { create(:project, :public) }

      it { expect(page).to have_content 'Build with confidence' }
      it { expect(page).to have_http_status(:success) }
    end

    context 'when project is private' do
      let(:project) { create(:project, :private) }

      it { expect(page).to have_content 'You need to sign in' }
    end
  end

  def visit_project_pipelines(**query)
    visit namespace_project_pipelines_path(project.namespace, project, query)
    wait_for_vue_resource
  end
end
