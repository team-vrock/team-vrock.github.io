document.addEventListener('DOMContentLoaded', () => {
    const topLink = document.querySelector('.floating-menu a[aria-label="Back to top"]');
    if (!topLink) return;

    topLink.removeAttribute('data-scroll');
    topLink.addEventListener('click', (event) => {
        if (window.location.pathname === '/' || window.location.pathname === '') {
            event.preventDefault();
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }
    });

    const searchLink = document.querySelector('.floating-menu a[aria-label="Posts"]');
    if (searchLink) {
        searchLink.addEventListener('click', () => {
            if (window.location.pathname === '/' || window.location.pathname === '') {
                window.setTimeout(() => document.querySelector('.vrock-search-input')?.focus(), 250);
            }
        });
    }
});
