document.addEventListener('DOMContentLoaded', async () => {
    const searchBox = document.getElementById('search-searchbar');
    const results = document.getElementById('search-hits');
    if (!searchBox || !results) return;

    const originalResults = results.innerHTML;
    const input = document.createElement('input');
    input.type = 'search';
    input.className = 'vrock-search-input';
    input.placeholder = 'Search posts...';
    input.setAttribute('aria-label', 'Search posts');
    searchBox.appendChild(input);

    const escapeHtml = (value) => String(value || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');

    let posts = [];
    try {
        const response = await fetch('/search.json');
        if (!response.ok) throw new Error('Search index unavailable');
        posts = await response.json();
    } catch (error) {
        return;
    }

    const renderPost = (post) => {
        const image = post.image
            ? `<div class="images-left"><img alt="" src="${escapeHtml(post.image)}"><p class="post-date">${escapeHtml(post.formatted_date)}</p></div>`
            : '';
        const date = post.image ? '' : escapeHtml(post.formatted_date);
        return `<article class="user-projects post-card${post.image ? '' : ' post-card-no-image'}">
            <h3 class="post-title">${escapeHtml(post.title)}</h3>
            ${image}
            <div class="contents-right">
                <p>${post.desc || ''}</p>
                <p class="post-date${post.image ? ' post-date-placeholder' : ''}">${date}</p>
                <a class="project-link" href="${escapeHtml(post.url)}">Read post</a>
            </div>
        </article>`;
    };

    posts = posts.map((post) => ({
        ...post,
        formatted_date: post.date ? new Date(post.date).toLocaleDateString('en-US', {
            year: 'numeric', month: 'long', day: 'numeric'
        }) : ''
    }));

    input.addEventListener('input', () => {
        const query = input.value.trim().toLowerCase();
        if (!query) {
            results.innerHTML = originalResults;
            return;
        }

        const matches = posts.filter((post) => {
            const haystack = [post.title, post.desc, post.category, post.tags].join(' ').toLowerCase();
            return haystack.includes(query);
        });

        results.innerHTML = matches.length
            ? matches.map(renderPost).join('')
            : '<div class="empty-state"><p>No posts found.</p></div>';
    });

    if (window.location.hash === '#searchlist' || new URLSearchParams(window.location.search).has('search')) {
        window.setTimeout(() => input.focus(), 250);
    }
});
