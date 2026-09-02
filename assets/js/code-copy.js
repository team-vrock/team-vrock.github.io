document.addEventListener('DOMContentLoaded', () => {
    const copyText = async (text) => {
        if (navigator.clipboard && window.isSecureContext) {
            await navigator.clipboard.writeText(text);
            return;
        }

        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.setAttribute('readonly', '');
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        textarea.remove();
    };

    document.querySelectorAll('.highlight').forEach((block) => {
        if (block.querySelector('.copy-code-button')) return;

        const code = block.querySelector('code');
        if (!code) return;

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'copy-code-button';
        button.textContent = 'Copy';
        button.setAttribute('aria-label', 'Copy code to clipboard');

        button.addEventListener('click', async () => {
            button.classList.remove('is-copied', 'has-error');

            try {
                await copyText(code.textContent);
                button.textContent = 'Copied';
                button.setAttribute('aria-label', 'Code copied');
                button.classList.add('is-copied');
            } catch (error) {
                button.textContent = 'Failed';
                button.setAttribute('aria-label', 'Copy failed');
                button.classList.add('has-error');
            }

            window.setTimeout(() => {
                button.textContent = 'Copy';
                button.setAttribute('aria-label', 'Copy code to clipboard');
                button.classList.remove('is-copied', 'has-error');
            }, 1600);
        });

        block.appendChild(button);
    });
});
