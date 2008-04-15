#--
# Copyright (c) 2008 Ryan Grove <ryan@wonko.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#   * Neither the name of this project nor the names of its contributors may be
#     used to endorse or promote products derived from this software without
#     specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#++

class PostController < Ramaze::Controller
  helper :admin, :cache, :cookie, :error, :wiki
  layout '/layout'
  
  deny_layout :atom
  
  view_root Thoth::Config.theme.view/:post,
            Thoth::VIEW_DIR/:post
  
  if Thoth::Config.server.enable_cache
    cache :atom, :ttl => 120
  end

  def index(name = nil)
    error_404 unless name && @post = Post.get(name)

    @title      = @post.title
    @author     = cookie(:thoth_author, '')
    @author_url = cookie(:thoth_author_url, '')
    
    @feeds = [{
      :href  => @post.atom_url,
      :title => 'Comments on this post',
      :type  => 'application/atom+xml'
    }]
  end
  
  def atom(name = nil)
    error_404 unless name && post = Post.get(name)
    
    comments = post.comments.reverse_order.limit(20)
    updated  = comments.count > 0 ? comments.first.created_at.xmlschema :
        post.created_at.xmlschema

    response['Content-Type'] = 'application/atom+xml'

    x = Builder::XmlMarkup.new(:indent => 2)
    x.instruct!

    x.feed(:xmlns => 'http://www.w3.org/2005/Atom') {
      x.id       post.url
      x.title    "Comments on \"#{post.title}\" - #{Thoth::Config.site.name}"
      x.updated  updated
      x.link     :href => post.url
      x.link     :href => post.atom_url, :rel => 'self'

      comments.all do |comment|
        x.entry {
          x.id        comment.url
          x.title     comment.title
          x.published comment.created_at.xmlschema
          x.updated   comment.updated_at.xmlschema
          x.link      :href => comment.url, :rel => 'alternate'
          x.content   comment.body_rendered, :type => 'html'

          x.author {
            x.name comment.author
            
            if comment.author_url && !comment.author_url.empty?
              x.uri comment.author_url
            end
          }
        }
      end
    }
  end
  
  def delete(id = nil)
    require_auth
    
    error_404 unless id && @post = Post[id]

    if request.post?
      if request[:confirm] == 'yes'
        @post.destroy
        action_cache.clear
        flash[:success] = 'Blog post deleted.'
        redirect(R(MainController))
      else
        redirect(@post.url)
      end
    end
    
    @title = "Delete Post: #{@post.title}"
  end
  
  def edit(id = nil)
    require_auth

    unless @post = Post[id]
      flash[:error] = 'Invalid post id.'
      redirect(Rs(:new))
    end
    
    if request.post?
      @post.title = request[:title]
      @post.body  = request[:body]
      @post.tags  = request[:tags]
      
      if @post.valid? && request[:action] == 'Post'
        begin
          Thoth.db.transaction do
            raise unless @post.save && @post.tags = request[:tags]
          end
        rescue => e
          @post_error = "There was an error saving your post: #{e}"
        else
          action_cache.clear
          flash[:success] = 'Blog post saved.'
          redirect(Rs(@post.name))
        end
      end
    end

    @title       = "Edit blog post - #{@post.title}"
    @form_action = Rs(:edit, id)
  end
  
  def list(page = 1)
    require_auth
    
    page = page.to_i
    
    @columns  = [:id, :title, :created_at, :updated_at]
    @order    = (request[:order] || :desc).to_sym
    @sort     = (request[:sort]  || :created_at).to_sym
    @sort     = :created_at unless @columns.include?(@sort)
    @sort_url = Rs(:list, page)

    @posts = Post.paginate(page, 20).order(@order == :desc ? @sort.desc : @sort)
    @title = "Blog Posts (page #{@page} of #{@posts.page_count})"

    @prev_url  = @posts.prev_page ? Rs(:list, @posts.prev_page, :sort => @sort,
        :order => @order) : nil
    @next_url  = @posts.next_page ? Rs(:list, @posts.next_page, :sort => @sort,
        :order => @order) : nil
  end
  
  def new
    require_auth

    @title       = "New blog post - Untitled"
    @form_action = Rs(:new)
    
    if request.post?
      @post = Post.new do |p|
        p.title = request[:title]
        p.body  = request[:body]
        p.tags  = request[:tags]
      end
      
      if @post.valid? && request[:action] == 'Post'
        begin
          Thoth.db.transaction do
            raise unless @post.save && @post.tags = request[:tags]
          end
        rescue => e
          @post_error = "There was an error saving your post: #{e}"
        else
          action_cache.clear
          flash[:success] = 'Blog post created.'
          redirect(Rs(@post.name))
        end
      end

      @title = "New blog post - #{@post.title}"
    end
  end
end
